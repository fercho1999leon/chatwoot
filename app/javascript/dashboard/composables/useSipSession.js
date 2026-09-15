// SIP.js session for Chatwoot telephony (CE). One UserAgent per tab, created on
// demand with credentials from POST /telephony/browser_session. The agent's leg is
// an INVITE originated by the telephony-controller via ARI; we never auto-accept:
// the agent must click "Connect audio". Mute is local (track.enabled). DTMF goes
// through the controller (single path), not from the browser.
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
let refreshTimer = null;
let unloadHooked = false;
let lockTimer = null;

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
    if (invitation && invitation.state !== SessionState.Terminated) {
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
  };

  const onInvite = inv => {
    // Only one owner of the microphone: never take a SIP call while a
    // WhatsApp/Twilio call is active in this tab.
    if (callsStore.hasActiveCall || invitation) {
      inv.reject().catch(() => {});
      return;
    }
    invitation = inv;
    store.hasInvitation = true;
    if (store.autoAcceptInvitation) {
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
      }
      if (state === SessionState.Terminated) {
        if (invitation === inv) invitation = null;
        store.hasInvitation = false;
        store.audioConnected = false;
        store.isMuted = false;
      }
    });
  };

  const disconnect = async () => {
    clearTimeout(refreshTimer);
    clearInterval(lockTimer);
    teardownSession();
    try {
      if (registerer) await registerer.unregister().catch(() => {});
      if (userAgent) await userAgent.stop().catch(() => {});
    } finally {
      registerer = null;
      userAgent = null;
      store.setSipStatus(SIP_STATUS.IDLE);
    }
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
      await disconnect();
      userAgent = new UserAgent({
        uri: UserAgent.makeURI(session.sip.uri),
        transportOptions: { server: session.sip.ws_url },
        authorizationUsername: session.sip.username,
        authorizationPassword: session.sip.password,
        sessionDescriptionHandlerFactoryOptions: {
          peerConnectionConfiguration: { iceServers: session.ice_servers },
        },
        delegate: { onInvite },
        logLevel: 'error',
      });
      userAgent.transport.stateChange.addListener(state => {
        if (
          state === 'Disconnected' &&
          store.sipStatus === SIP_STATUS.REGISTERED
        ) {
          store.setSipStatus(SIP_STATUS.FAILED, 'transport');
        }
      });
      await userAgent.start();
      registerer = new Registerer(userAgent, { expires: 120 });
      registerer.stateChange.addListener(state => {
        if (state === RegistererState.Registered)
          store.setSipStatus(SIP_STATUS.REGISTERED);
        else if (state === RegistererState.Terminated)
          store.setSipStatus(SIP_STATUS.IDLE);
      });
      await registerer.register();
      holdLock();
      requestCallNotificationPermission();
      hookUnload(disconnect);
      // TURN credentials expire: refresh the session before they do.
      const ttl = Math.max(
        60,
        (new Date(session.expires_at) - Date.now()) / 1000 - 120
      );
      clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        if (!store.hasActiveCall && !lockHeldByOtherTab())
          connect({ force: true });
      }, ttl * 1000);
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

  return { connect, disconnect, acceptInvitation, setMuted, hangupLocal };
};
