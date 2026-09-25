import { nextTick } from 'vue';
import { setActivePinia, createPinia } from 'pinia';
import TelephonyAPI from 'dashboard/api/telephony';
import {
  useTelephonyStore,
  TELEPHONY_STATES,
} from 'dashboard/stores/telephony';
import { useSipSession } from '../useSipSession';

let lastUserAgentOptions = null;

vi.mock('sip.js', () => {
  const stateChange = () => ({ addListener: () => {} });
  // Constructors returning plain objects: enough of SIP.js for connect() to succeed.
  function UserAgent(options) {
    lastUserAgentOptions = options;
    return {
      transport: { stateChange: stateChange(), isConnected: () => true },
      start: () => Promise.resolve(),
      stop: () => Promise.resolve(),
    };
  }
  UserAgent.makeURI = uri => uri;
  function Registerer() {
    return {
      stateChange: stateChange(),
      state: 'Registered',
      register: () => Promise.resolve(),
      unregister: () => Promise.resolve(),
    };
  }
  return {
    UserAgent,
    Registerer,
    RegistererState: {
      Registered: 'Registered',
      Unregistered: 'Unregistered',
      Terminated: 'Terminated',
    },
    SessionState: {
      Initial: 'Initial',
      Establishing: 'Establishing',
      Established: 'Established',
      Terminating: 'Terminating',
      Terminated: 'Terminated',
    },
  };
});

vi.mock('dashboard/api/telephony', () => ({
  default: { browserSession: vi.fn() },
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({ hasActiveCall: false }),
}));
vi.mock('dashboard/composables/useCallNotification', () => ({
  requestCallNotificationPermission: () => {},
}));

const ME = 1;

const call = (overrides = {}) => ({
  id: 'call-1',
  state: TELEPHONY_STATES.ANSWERED,
  state_version: 3,
  user_id: ME,
  participants: [],
  ringing_user_ids: [],
  ...overrides,
});

// Controller legs carry X-Chatwoot-Call-Id; FreePBX's own INVITEs (calls it routes) do not.
const fakeInvitation = (state, { fromPbx = false } = {}) => {
  const listeners = [];
  const sender = { track: { enabled: true } };
  return {
    state,
    request: {
      getHeader: name =>
        !fromPbx && name === 'X-Chatwoot-Call-Id' ? 'call-1' : undefined,
    },
    remoteIdentity: { uri: { user: '0987654321' }, displayName: 'Ana' },
    bye: vi.fn(() => Promise.resolve()),
    reject: vi.fn(() => Promise.resolve()),
    accept: vi.fn(() => Promise.resolve()),
    invite: vi.fn(options => {
      options?.requestDelegate?.onAccept?.();
      return Promise.resolve();
    }),
    refer: vi.fn(() => Promise.resolve()),
    sessionDescriptionHandler: {
      sendDtmf: vi.fn(() => true),
      peerConnection: { getSenders: () => [sender], getReceivers: () => [] },
    },
    sender,
    stateChange: { addListener: vi.fn(cb => listeners.push(cb)) },
    emit(next) {
      this.state = next;
      listeners.forEach(cb => cb(next));
    },
  };
};

// The composable is a module singleton bound to the first store it sees: one pinia for the file.
setActivePinia(createPinia());

describe('useSipSession', () => {
  let store;
  let sip;

  beforeEach(async () => {
    vi.useFakeTimers();
    store = useTelephonyStore();
    store.$reset();
    store.currentUserId = ME;
    TelephonyAPI.browserSession.mockResolvedValue({
      sip: { uri: 'sip:100@pbx', ws_url: 'wss://pbx/ws', username: '100' },
      ice_servers: [],
      expires_at: new Date(Date.now() + 3600 * 1000).toISOString(),
    });
    sip = useSipSession();
    await sip.connect({ force: true });
  });

  afterEach(async () => {
    await sip.disconnect();
    vi.useRealTimers();
  });

  const ring = (state, opts) => {
    const inv = fakeInvitation(state, opts);
    lastUserAgentOptions.delegate.onInvite(inv);
    if (state === 'Established') store.audioConnected = true;
    return inv;
  };

  it('sends BYE on the established leg when the controller ends the call', async () => {
    store.applyCall(call(), ME);
    const inv = ring('Established');

    store.applyCall(
      call({ state: TELEPHONY_STATES.ENDED, state_version: 4 }),
      ME
    );
    await nextTick();

    expect(inv.bye).toHaveBeenCalledTimes(1);
    expect(inv.reject).not.toHaveBeenCalled();
    expect(store.audioConnected).toBe(false);
    expect(store.hasInvitation).toBe(false);
  });

  it('rejects a ringing leg when someone else answered', async () => {
    store.applyCall(call({ user_id: 2, ringing_user_ids: [ME] }), ME);
    const inv = ring('Initial');

    store.applyCall(
      call({ user_id: 2, participants: [3], state_version: 4 }),
      ME
    );
    await nextTick();

    expect(inv.reject).toHaveBeenCalledTimes(1);
    expect(inv.bye).not.toHaveBeenCalled();
    expect(store.hasInvitation).toBe(false);
  });

  it('sends BYE when the transfer completes on another agent', async () => {
    store.applyCall(call(), ME);
    const inv = ring('Established');

    store.applyCall(
      call({ user_id: 2, transfer_state: 'completed', state_version: 4 }),
      ME
    );
    await nextTick();

    expect(inv.bye).toHaveBeenCalledTimes(1);
    expect(store.lastEndedCall?.end_reason).toBe('transferred');
  });

  it('leaves a leg that is already terminating alone', async () => {
    store.applyCall(call(), ME);
    const inv = ring('Terminating');

    store.applyCall(
      call({ state: TELEPHONY_STATES.ENDED, state_version: 4 }),
      ME
    );
    await nextTick();

    expect(inv.bye).not.toHaveBeenCalled();
    expect(inv.reject).not.toHaveBeenCalled();
  });

  it('keeps orphaned audio up so the agent can hang up by hand', async () => {
    store.applyCall(call({ user_id: 2, participants: [ME] }), ME);
    const inv = ring('Established');

    store.applyCall(
      call({ user_id: 2, participants: [], state_version: 4 }),
      ME
    );
    await nextTick();

    expect(store.hasOrphanAudio).toBe(true);
    expect(inv.bye).not.toHaveBeenCalled();
    expect(store.audioConnected).toBe(true);
  });

  describe('legs sent by FreePBX (calls it routes)', () => {
    // jsdom has no WebRTC: attachRemoteStream only needs a track container.
    beforeEach(() => {
      vi.stubGlobal(
        'MediaStream',
        vi.fn(() => ({ addTrack: vi.fn() }))
      );
    });
    afterEach(() => vi.unstubAllGlobals());

    it('shows a card with the caller and never auto-accepts it', async () => {
      store.autoAcceptInvitation = true;
      const inv = ring('Initial', { fromPbx: true });

      expect(inv.accept).not.toHaveBeenCalled();
      expect(store.pbxSession).toMatchObject({
        remote_number: '0987654321',
        remote_name: 'Ana',
        answered: false,
      });
      expect(store.isIncoming).toBe(true);
      expect(store.showWidget).toBe(true);
    });

    it('holds by re-INVITE, sends RFC 4733 DTMF and transfers by REFER', async () => {
      const inv = ring('Initial', { fromPbx: true });
      inv.emit('Established');
      expect(store.pbxSession.answered).toBe(true);
      expect(store.isIncoming).toBe(false);

      await sip.setHold(true);
      expect(inv.sessionDescriptionHandlerOptionsReInvite).toEqual({
        hold: true,
      });
      expect(inv.invite).toHaveBeenCalledTimes(1);
      expect(store.isOnHold).toBe(true);
      expect(inv.sender.track.enabled).toBe(false);
      await sip.setHold(false);
      expect(store.isOnHold).toBe(false);
      expect(inv.sender.track.enabled).toBe(true);

      expect(sip.sendDtmf('5')).toBe(true);
      expect(inv.sessionDescriptionHandler.sendDtmf).toHaveBeenCalledWith('5');

      await sip.transfer('700');
      expect(inv.refer).toHaveBeenCalledWith('sip:700@pbx');
    });

    it('clears the card when FreePBX hangs up the leg', async () => {
      const inv = ring('Initial', { fromPbx: true });
      inv.emit('Established');
      inv.emit('Terminated');

      expect(store.pbxSession).toBeNull();
      expect(store.audioConnected).toBe(false);
    });

    it('does not use SIP controls on legs originated by the controller', async () => {
      store.applyCall(call(), ME);
      const inv = ring('Initial');
      inv.emit('Established');

      expect(store.pbxSession).toBeNull();
      expect(await sip.setHold(true)).toBe(false);
      expect(sip.sendDtmf('1')).toBe(false);
      expect(await sip.transfer('700')).toBe(false);
      expect(inv.invite).not.toHaveBeenCalled();
    });
  });
});
