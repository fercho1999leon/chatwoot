// SIP.js session for Chatwoot telephony (CE). One UserAgent per tab, created on
// demand with credentials from POST /telephony/browser_session. The agent's leg is
// an INVITE originated by the telephony-controller via ARI; we never auto-accept:
// the agent must click "Connect audio". Mute is local (track.enabled). DTMF goes
// through the controller (single path), not from the browser.
import { Registerer, RegistererState, SessionState, UserAgent } from 'sip.js';
import TelephonyAPI from 'dashboard/api/telephony';
import { useTelephonyStore, SIP_STATUS } from 'dashboard/stores/telephony';
import { useCallsStore } from 'dashboard/stores/calls';

// Module-level singletons: navigating between conversations must not drop the call.
let userAgent = null;
let registerer = null;
let invitation = null;
let remoteAudio = null;
let refreshTimer = null;
let unloadHooked = false;

// Unregister when the tab goes away; otherwise the stale contact lingers in
// Asterisk until it expires and, with max_contacts reached, can evict the
// agent's live registration (the INVITE then rings a dead contact).
const hookUnload = disconnect => {
  if (unloadHooked) return;
  unloadHooked = true;
  window.addEventListener('pagehide', () => {
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

  // quiet: registration attempted on dashboard load; a user without a linked
  // extension (or feature off) must not see the widget in a failed state.
  const connect = async ({ force = false, quiet = false } = {}) => {
    if (userAgent && !force) return true;
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
      hookUnload(disconnect);
      // TURN credentials expire: refresh the session before they do.
      const ttl = Math.max(
        60,
        (new Date(session.expires_at) - Date.now()) / 1000 - 120
      );
      clearTimeout(refreshTimer);
      refreshTimer = setTimeout(() => {
        if (!store.hasActiveCall) connect({ force: true });
      }, ttl * 1000);
      return true;
    } catch (error) {
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
