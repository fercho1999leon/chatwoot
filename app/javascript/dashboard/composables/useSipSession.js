// SIP.js session for Chatwoot telephony (CE). One UserAgent per tab, created on
// demand with credentials from POST /telephony/browser_session. Two kinds of INVITE:
// - legs originated by the telephony-controller via ARI (X-Chatwoot-Call-Id header): hold,
//   transfer and DTMF go through the controller API (single path);
// - legs FreePBX sends to the agent's extension when it routes a call (queue, ring group,
//   IVR, transfer): the phone controls them over SIP — hold by re-INVITE (FreePBX plays its
//   music), blind transfer by REFER, RFC 4733 DTMF, local hang up.
// We never auto-accept a ringing call: the agent must click Answer. Mute is local (track.enabled).
import { watch } from 'vue';
import { Registerer, RegistererState, SessionState, UserAgent } from 'sip.js';
import TelephonyAPI from 'dashboard/api/telephony';
import { useTelephonyStore, SIP_STATUS } from 'dashboard/stores/telephony';
import { useCallsStore } from 'dashboard/stores/calls';
import { requestCallNotificationPermission } from 'dashboard/composables/useCallNotification';

// Module-level singletons: navigating between conversations must not drop the call.
let userAgent = null;
let registerer = null;
let invitation = null;
let remoteAudio = null;
let sipDomain = null; // host of the agent's SIP URI: REFER targets live in the same domain
let refreshTimer = null;
let unloadHooked = false;
let hangupWatchHooked = false;
let lockTimer = null;
let reconnectTimer = null;
let healthTimer = null;
let reconnectAttempts = 0;
const RECONNECT_BASE_MS = 2000;
const RECONNECT_MAX_MS = 60000;
// Reconnect deferred because a call is up: poll without growing the backoff.
const RECONNECT_DEFER_MS = 5000;
// TURN refresh skipped because a call is up: try again soon instead of dropping it.
const REFRESH_RETRY_MS = 30000;
const HEALTH_CHECK_MS = 60000;

// One registration per agent across tabs: with two tabs registered the PBX
// rings both and one of them rejects. The tab holding a fresh lock in
// localStorage registers; the others stand by and take over when it goes away.
const LOCK_KEY = 'telephony_sip_tab';
const LOCK_TTL_MS = 12000;
const LOCK_HEARTBEAT_MS = 4000;
const tabId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

const readLock = () => {
  try {
    return JSON.parse(localStorage.getItem(LOCK_KEY) || 'null');
  } catch (e) {
    return null;
  }
};
const lockHeldByOtherTab = () => {
  const lock = readLock();
  return !!lock && lock.id !== tabId && Date.now() - lock.ts < LOCK_TTL_MS;
};
const writeLock = () => {
  try {
    localStorage.setItem(
      LOCK_KEY,
      JSON.stringify({ id: tabId, ts: Date.now() })
    );
  } catch (e) {
    // storage unavailable: behave as a single tab
  }
};
const releaseLock = () => {
  try {
    if (readLock()?.id === tabId) localStorage.removeItem(LOCK_KEY);
  } catch (e) {
    // ignore
  }
};

// Unregister when the tab goes away; otherwise the stale contact lingers in
// Asterisk until it expires and, with max_contacts reached, can evict the
// agent's live registration (the INVITE then rings a dead contact).
const hookUnload = disconnect => {
  if (unloadHooked) return;
  unloadHooked = true;
  window.addEventListener('pagehide', () => {
    releaseLock();
    disconnect();
  });
};

const QUIET_REGISTER_ERRORS = ['no_endpoint', 'feature_disabled'];
// Present on every leg the controller originates towards an agent; absent on FreePBX's own INVITEs.
const CONTROLLER_CALL_HEADER = 'X-Chatwoot-Call-Id';

const isControllerLeg = inv =>
  !!inv.request?.getHeader?.(CONTROLLER_CALL_HEADER);

const ensureAudioElement = () => {
  if (remoteAudio) return remoteAudio;
  remoteAudio = document.createElement('audio');
  remoteAudio.autoplay = true;
  remoteAudio.setAttribute('data-telephony-remote-audio', '');
  document.body.appendChild(remoteAudio);
  return remoteAudio;
};

const attachRemoteStream = session => {
  const pc = session.sessionDescriptionHandler?.peerConnection;
  if (!pc) return;
  const stream = new MediaStream();
  pc.getReceivers().forEach(r => r.track && stream.addTrack(r.track));
  ensureAudioElement().srcObject = stream;
};

export const useSipSession = () => {
  const store = useTelephonyStore();
  const callsStore = useCallsStore();

  const teardownSession = () => {
    if (
      invitation &&
      ![SessionState.Terminated, SessionState.Terminating].includes(
        invitation.state
      )
    ) {
      try {
        if (invitation.state === SessionState.Established) invitation.bye();
        else invitation.reject();
      } catch (e) {
        // already gone
      }
    }
    invitation = null;
    store.hasInvitation = false;
    store.audioConnected = false;
    store.isMuted = false;
    store.setPbxSession(null);
  };

  // The controller closed the call for this tab (ended, transferred, answered elsewhere)
  // but may have failed to hang up the agent's leg: send BYE/reject ourselves. Orphaned
  // audio keeps its Hang up button instead: the store never requests a hangup for it.
  if (!hangupWatchHooked) {
    hangupWatchHooked = true;
    watch(() => store.localHangupRequests, teardownSession);
  }

  const onInvite = inv => {
    // Only one owner of the microphone: never take a SIP call while a
    // WhatsApp/Twilio call is active in this tab.
    if (callsStore.hasActiveCall || invitation) {
      inv.reject().catch(() => {});
      return;
    }
    invitation = inv;
    store.hasInvitation = true;
    const fromPbx = !isControllerLeg(inv);
    if (fromPbx) {
      // Card right away, even before (or without) the controller announcing the call.
      store.setPbxSession({
        remote_number: inv.remoteIdentity?.uri?.user || '',
        remote_name: inv.remoteIdentity?.displayName || '',
        answered: false,
        on_hold: false,
      });
    } else if (store.autoAcceptInvitation) {
      store.autoAcceptInvitation = false;
      // Declared below; only invoked at runtime once the composable is built.
      // eslint-disable-next-line no-use-before-define
      acceptInvitation(); // on failure (mic denied) the "Connect audio" button remains
    }
    inv.stateChange.addListener(state => {
      if (state === SessionState.Established) {
        attachRemoteStream(inv);
        store.audioConnected = true;
        store.hasInvitation = false;
        if (fromPbx) store.setPbxSession({ answered: true });
      }
      if (state === SessionState.Terminated) {
        if (invitation && invitation !== inv) return; // an older leg: the current one keeps the card
        invitation = null;
        store.hasInvitation = false;
        store.audioConnected = false;
        store.isMuted = false;
        if (fromPbx) store.setPbxSession(null);
        store.dropOrphanAudio(); // BYE on audio the controller no longer tracks: close the card
      }
    });
  };

  const disconnect = async () => {
    clearTimeout(refreshTimer);
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
    clearInterval(lockTimer);
    clearInterval(healthTimer);
    healthTimer = null;
    teardownSession();
    // Detach first: the state listeners of a torn-down UA/registerer must not schedule reconnects.
    const reg = registerer;
    const ua = userAgent;
    registerer = null;
    userAgent = null;
    try {
      if (reg) await reg.unregister().catch(() => {});
      if (ua) await ua.stop().catch(() => {});
    } finally {
      store.setSipStatus(SIP_STATUS.IDLE);
    }
  };

  const sessionLive = () =>
    store.hasActiveCall || store.hasInvitation || store.audioConnected;

  // Transport lost / registration lost (proxy restart, network blip): re-register with
  // backoff instead of waiting for the agent to press Retry. A live call keeps its media;
  // only signalling returns. One pending timer at a time; a reconnect deferred because a
  // call is up polls every few seconds without growing the backoff.
  const scheduleReconnect = ({ deferred = false } = {}) => {
    if (reconnectTimer) return;
    let delay = RECONNECT_DEFER_MS;
    if (!deferred) {
      delay = Math.min(
        RECONNECT_BASE_MS * 2 ** reconnectAttempts,
        RECONNECT_MAX_MS
      );
      reconnectAttempts += 1;
    }
    reconnectTimer = setTimeout(async () => {
      reconnectTimer = null;
      if (store.sipStatus !== SIP_STATUS.FAILED) return;
      // connect() tears the current session down: never while a call is up or ringing —
      // the agent still has "Reconnect audio" for that case.
      if (sessionLive()) {
        scheduleReconnect({ deferred: true });
        return;
      }
      // eslint-disable-next-line no-use-before-define
      const ok = await connect({ force: true, quiet: true });
      if (ok) reconnectAttempts = 0;
      else scheduleReconnect();
    }, delay);
  };

  const failAndReconnect = reason => {
    store.setSipStatus(SIP_STATUS.FAILED, reason);
    scheduleReconnect();
  };

  // Belt and braces for missed state events: every minute make sure the registration
  // and the WebSocket are really up; otherwise go through the reconnect path.
  const startHealthCheck = () => {
    clearInterval(healthTimer);
    healthTimer = setInterval(() => {
      if (
        [SIP_STATUS.IDLE, SIP_STATUS.STANDBY, SIP_STATUS.CONNECTING].includes(
          store.sipStatus
        )
      )
        return;
      if (reconnectTimer) return; // already on its way
      const registered = registerer?.state === RegistererState.Registered;
      const connected = !!userAgent?.transport?.isConnected?.();
      if (registered && connected) return;
      // A failed connect() already carries a precise code: keep it.
      if (store.sipStatus === SIP_STATUS.FAILED) scheduleReconnect();
      else failAndReconnect(registered ? 'transport' : 'registration');
    }, HEALTH_CHECK_MS);
  };

  // TURN credentials expire: refresh the session before they do. Never mid-call
  // (connect() drops the media): retry a bit later instead of losing the refresh.
  const scheduleRefresh = delayMs => {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(() => {
      if (lockHeldByOtherTab()) return;
      if (sessionLive()) {
        scheduleRefresh(REFRESH_RETRY_MS);
        return;
      }
      // eslint-disable-next-line no-use-before-define
      connect({ force: true });
    }, delayMs);
  };

  // Standby tab: poll the lock and register once the active tab is gone.
  const watchLock = () => {
    clearInterval(lockTimer);
    lockTimer = setInterval(() => {
      // eslint-disable-next-line no-use-before-define
      if (!lockHeldByOtherTab()) connect({ quiet: true });
    }, LOCK_HEARTBEAT_MS);
  };

  // Active tab: keep the lock fresh; yield if another tab took it over ("Use this tab").
  const holdLock = () => {
    writeLock();
    clearInterval(lockTimer);
    lockTimer = setInterval(async () => {
      if (!lockHeldByOtherTab()) {
        writeLock();
        return;
      }
      if (store.hasActiveCall || store.hasInvitation) return; // finish the call first
      await disconnect();
      store.setSipStatus(SIP_STATUS.STANDBY);
      watchLock();
    }, LOCK_HEARTBEAT_MS);
  };

  // quiet: registration attempted on dashboard load; a user without a linked
  // extension (or feature off) must not see the widget in a failed state.
  // force: re-register even if already registered, and take the lock over from another tab.
  const connect = async ({ force = false, quiet = false } = {}) => {
    if (userAgent && !force) return true;
    if (!force && lockHeldByOtherTab()) {
      store.setSipStatus(SIP_STATUS.STANDBY);
      watchLock();
      return false;
    }
    clearInterval(lockTimer);
    writeLock();
    store.setSipStatus(SIP_STATUS.CONNECTING);
    try {
      const session = await TelephonyAPI.browserSession();
      await disconnect(); // leaves the status IDLE
      sipDomain = session.sip.realm || session.sip.uri.split('@')[1];
      store.setSipStatus(SIP_STATUS.CONNECTING);
      const ua = new UserAgent({
        uri: UserAgent.makeURI(session.sip.uri),
        // CRLF keep-alives keep the WebSocket alive through proxies while a call has no SIP traffic.
        transportOptions: {
          server: session.sip.ws_url,
          keepAliveInterval: 25,
        },
        authorizationUsername: session.sip.username,
        authorizationPassword: session.sip.password,
        sessionDescriptionHandlerFactoryOptions: {
          peerConnectionConfiguration: { iceServers: session.ice_servers },
        },
        delegate: { onInvite },
        logLevel: 'error',
      });
      userAgent = ua;
      ua.transport.stateChange.addListener(state => {
        if (userAgent !== ua) return; // replaced or torn down
        if (state !== 'Disconnected') return;
        if ([SIP_STATUS.IDLE, SIP_STATUS.STANDBY].includes(store.sipStatus))
          return;
        failAndReconnect('transport');
      });
      await ua.start();
      const reg = new Registerer(ua, { expires: 120 });
      registerer = reg;
      reg.stateChange.addListener(state => {
        if (registerer !== reg) return; // replaced or torn down
        if (state === RegistererState.Registered) {
          store.setSipStatus(SIP_STATUS.REGISTERED);
          // Registration back while a call is up without audio: ask the PBX to ring us again.
          if (store.needsReinvite) store.reinvite().catch(() => {});
        } else if (state === RegistererState.Unregistered) {
          // Refresh rejected / PBX dropped the contact: the widget would otherwise sit "registered".
          failAndReconnect('registration');
        } else if (state === RegistererState.Terminated) {
          store.setSipStatus(SIP_STATUS.IDLE);
        }
      });
      await reg.register();
      reconnectAttempts = 0;
      holdLock();
      startHealthCheck();
      requestCallNotificationPermission();
      hookUnload(disconnect);
      const ttl = Math.max(
        60,
        (new Date(session.expires_at) - Date.now()) / 1000 - 120
      );
      scheduleRefresh(ttl * 1000);
      return true;
    } catch (error) {
      releaseLock();
      const code = error?.response?.data?.code || error?.message || 'unknown';
      if (quiet && QUIET_REGISTER_ERRORS.includes(code)) {
        store.setSipStatus(SIP_STATUS.IDLE);
      } else {
        store.setSipStatus(SIP_STATUS.FAILED, code);
      }
      return false;
    }
  };

  const acceptInvitation = async () => {
    if (!invitation) return false;
    if (invitation.state !== SessionState.Initial) return true; // accept already in progress
    try {
      await invitation.accept({
        sessionDescriptionHandlerOptions: {
          constraints: { audio: true, video: false },
        },
      });
      return true;
    } catch (error) {
      store.setSipStatus(
        store.sipStatus,
        error?.name === 'NotAllowedError' ? 'microphone' : error?.message
      );
      return false;
    }
  };

  const setMuted = muted => {
    const pc = invitation?.sessionDescriptionHandler?.peerConnection;
    if (!pc) return;
    pc.getSenders().forEach(s => {
      if (s.track) s.track.enabled = !muted;
    });
    store.isMuted = muted;
  };

  const hangupLocal = () => teardownSession();

  // ── FreePBX-routed legs: SIP controls ──
  const establishedPbxLeg = () =>
    store.pbxSession && invitation?.state === SessionState.Established
      ? invitation
      : null;

  // Hold by re-INVITE (a=sendonly): FreePBX plays its music on hold to the caller.
  const setHold = async hold => {
    const session = establishedPbxLeg();
    if (!session) return false;
    session.sessionDescriptionHandlerOptionsReInvite = { hold };
    await session.invite({
      requestDelegate: {
        onAccept: () => {
          const pc = session.sessionDescriptionHandler?.peerConnection;
          pc?.getSenders().forEach(sender => {
            if (sender.track) sender.track.enabled = !hold && !store.isMuted;
          });
          store.setPbxSession({ on_hold: hold });
        },
      },
    });
    return true;
  };

  // RFC 4733 (RTP events) through the WebRTC DTMF sender.
  const sendDtmf = digit => {
    const session = establishedPbxLeg();
    return !!session?.sessionDescriptionHandler?.sendDtmf(digit);
  };

  // Blind transfer: FreePBX takes the call to the extension, queue or ring group and hangs up our leg.
  const transfer = async target => {
    const session = establishedPbxLeg();
    const number = String(target).replace(/[^0-9*#+]/g, '');
    if (!session || !number || !sipDomain) return false;
    await session.refer(UserAgent.makeURI(`sip:${number}@${sipDomain}`));
    return true;
  };

  return {
    connect,
    disconnect,
    acceptInvitation,
    setMuted,
    hangupLocal,
    setHold,
    sendDtmf,
    transfer,
  };
};
