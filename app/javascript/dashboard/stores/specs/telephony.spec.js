import { setActivePinia, createPinia } from 'pinia';
import TelephonyAPI from 'dashboard/api/telephony';
import { useTelephonyStore, TELEPHONY_STATES } from '../telephony';

vi.mock('dashboard/api/telephony', () => ({
  default: {
    activeCall: vi.fn(),
    show: vi.fn(),
    leave: vi.fn(),
  },
}));

const ME = 1;
const OWNER = 2;

// Conference call owned by someone else where this agent is a participant.
const joinedCall = (overrides = {}) => ({
  id: 'call-1',
  state: TELEPHONY_STATES.ANSWERED,
  state_version: 3,
  user_id: OWNER,
  participants: [ME],
  ringing_user_ids: [],
  ...overrides,
});

describe('telephony store', () => {
  let store;

  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
    store = useTelephonyStore();
    store.currentUserId = ME;
    store.activeCall = joinedCall();
    store.audioConnected = true;
  });

  describe('refreshActive', () => {
    it('keeps the call when active is empty but the SIP audio is up and the call goes on', async () => {
      TelephonyAPI.activeCall.mockResolvedValue(null);
      TelephonyAPI.show.mockResolvedValue(
        joinedCall({ state_version: 4, participants: [] })
      );

      await store.refreshActive();

      expect(TelephonyAPI.show).toHaveBeenCalledWith('call-1');
      expect(store.activeCall).not.toBeNull();
      expect(store.activeCall.state).toBe(TELEPHONY_STATES.ANSWERED);
      expect(store.hasActiveCall).toBe(true);
      expect(store.orphanAudio).toBe(true);
      expect(store.hasOrphanAudio).toBe(true);
      expect(store.lastEndedCall).toBeNull();
    });

    it('ends the call when the call itself reports ended', async () => {
      TelephonyAPI.activeCall.mockResolvedValue(null);
      TelephonyAPI.show.mockResolvedValue(
        joinedCall({ state: TELEPHONY_STATES.ENDED, state_version: 9 })
      );

      await store.refreshActive();

      expect(store.activeCall).toBeNull();
      expect(store.lastEndedCall?.state).toBe(TELEPHONY_STATES.ENDED);
      expect(store.audioConnected).toBe(false);
    });

    it('ends the call when the call no longer exists (404)', async () => {
      TelephonyAPI.activeCall.mockResolvedValue(null);
      TelephonyAPI.show.mockRejectedValue({ response: { status: 404 } });

      await store.refreshActive();

      expect(store.activeCall).toBeNull();
      expect(store.lastEndedCall?.state).toBe(TELEPHONY_STATES.ENDED);
    });

    it('keeps the card on a transient error re-reading the call', async () => {
      TelephonyAPI.activeCall.mockResolvedValue(null);
      TelephonyAPI.show.mockRejectedValue({ response: { status: 502 } });

      await store.refreshActive();

      expect(store.activeCall).not.toBeNull();
      expect(store.lastEndedCall).toBeNull();
    });

    it('ends the call when active is empty and no SIP session is live', async () => {
      store.audioConnected = false;
      TelephonyAPI.activeCall.mockResolvedValue(null);

      await store.refreshActive();

      expect(TelephonyAPI.show).not.toHaveBeenCalled();
      expect(store.activeCall).toBeNull();
      expect(store.lastEndedCall?.state).toBe(TELEPHONY_STATES.ENDED);
    });
  });

  describe('applyCall', () => {
    it('keeps the call as orphan audio when this agent is dropped while audio is connected', () => {
      store.applyCall(joinedCall({ state_version: 4, participants: [] }), ME);

      expect(store.activeCall).not.toBeNull();
      expect(store.activeCall.state_version).toBe(4);
      expect(store.orphanAudio).toBe(true);
      expect(store.hasOrphanAudio).toBe(true);
      expect(store.audioConnected).toBe(true);
    });

    it('drops the call silently when this agent is dropped without audio', () => {
      store.audioConnected = false;

      store.applyCall(joinedCall({ state_version: 4, participants: [] }), ME);

      expect(store.activeCall).toBeNull();
      expect(store.orphanAudio).toBe(false);
      expect(store.lastEndedCall).toBeNull();
    });

    it('clears the orphan flag once this agent is involved again', () => {
      store.applyCall(joinedCall({ state_version: 4, participants: [] }), ME);
      store.applyCall(joinedCall({ state_version: 5 }), ME);

      expect(store.orphanAudio).toBe(false);
      expect(store.hasOrphanAudio).toBe(false);
      expect(store.activeCall.state_version).toBe(5);
    });

    it('resets the orphan flag when the call ends', () => {
      store.applyCall(joinedCall({ state_version: 4, participants: [] }), ME);
      store.applyCall(
        joinedCall({ state: TELEPHONY_STATES.ENDED, state_version: 6 }),
        ME
      );

      expect(store.activeCall).toBeNull();
      expect(store.orphanAudio).toBe(false);
      expect(store.hasOrphanAudio).toBe(false);
    });

    describe('version gates', () => {
      it('does not resurrect a call from a snapshot older than its ended version', () => {
        const ended = joinedCall({
          state: TELEPHONY_STATES.ENDED,
          state_version: 11,
          end_reason: 'hangup',
        });
        store.applyCall(ended, ME);
        store.applyCall(joinedCall({ state_version: 10 }), ME);

        expect(store.activeCall).toBeNull();
        expect(store.hasActiveCall).toBe(false);
        expect(store.endedVersions['call-1']).toBe(11);
        expect(store.lastEndedCall).toEqual(ended);
      });

      it('keeps the newest ended snapshot when an older ended one arrives late', () => {
        const ended = joinedCall({
          state: TELEPHONY_STATES.ENDED,
          state_version: 11,
          end_reason: 'hangup',
        });
        store.applyCall(ended, ME);
        store.applyCall(
          joinedCall({ state: TELEPHONY_STATES.ENDED, state_version: 9 }),
          ME
        );

        expect(store.lastEndedCall).toEqual(ended);
        expect(store.endedVersions['call-1']).toBe(11);
      });

      it('ignores a stale snapshot of the current call even when it drops this agent', () => {
        store.applyCall(joinedCall({ state_version: 5 }), ME);
        const requests = store.localHangupRequests;

        store.applyCall(joinedCall({ state_version: 3, participants: [] }), ME);

        expect(store.activeCall.state_version).toBe(5);
        expect(store.activeCall.participants).toEqual([ME]);
        expect(store.orphanAudio).toBe(false);
        expect(store.audioConnected).toBe(true);
        expect(store.localHangupRequests).toBe(requests);
      });

      it('does not let another call replace the one holding the SIP leg', () => {
        store.applyCall(
          joinedCall({ id: 'call-2', state_version: 1, user_id: ME }),
          ME
        );

        expect(store.activeCall.id).toBe('call-1');
        expect(store.orphanAudio).toBe(false);
      });

      it('lets another call replace the current one once no SIP leg is up', () => {
        store.audioConnected = false;

        store.applyCall(
          joinedCall({ id: 'call-2', state_version: 1, user_id: ME }),
          ME
        );

        expect(store.activeCall.id).toBe('call-2');
      });

      it('keeps at most 20 ended versions', () => {
        store.audioConnected = false;
        for (let i = 1; i <= 25; i += 1) {
          store.applyCall(
            joinedCall({ id: `call-${i}`, state_version: 1 }),
            ME
          );
          store.applyCall(
            joinedCall({
              id: `call-${i}`,
              state: TELEPHONY_STATES.ENDED,
              state_version: 2,
            }),
            ME
          );
        }

        const ids = Object.keys(store.endedVersions);
        expect(ids).toHaveLength(20);
        expect(ids[0]).toBe('call-6');
        expect(ids[19]).toBe('call-25');
        expect(store.endedVersions['call-1']).toBeUndefined();
      });
    });

    describe('local hangup requests', () => {
      it('asks the SIP leg to hang up when the call ends', () => {
        store.applyCall(
          joinedCall({ state: TELEPHONY_STATES.ENDED, state_version: 6 }),
          ME
        );

        expect(store.localHangupRequests).toBe(1);
      });

      it('asks the SIP leg to hang up when the transfer completes elsewhere', () => {
        store.applyCall(
          joinedCall({
            state_version: 6,
            participants: [],
            transfer_state: 'completed',
          }),
          ME
        );

        expect(store.activeCall).toBeNull();
        expect(store.lastEndedCall?.end_reason).toBe('transferred');
        expect(store.localHangupRequests).toBe(1);
      });

      it('rejects the ringing leg when someone else answered', () => {
        store.audioConnected = false;
        store.hasInvitation = true;

        store.applyCall(joinedCall({ state_version: 6, participants: [] }), ME);

        expect(store.activeCall).toBeNull();
        expect(store.localHangupRequests).toBe(1);
      });

      it('never hangs up orphaned audio automatically', () => {
        store.applyCall(joinedCall({ state_version: 6, participants: [] }), ME);

        expect(store.orphanAudio).toBe(true);
        expect(store.localHangupRequests).toBe(0);
      });
    });
  });

  describe('leaveCall', () => {
    it('shows a "left" closing card and clears the session flags', async () => {
      store.isMuted = true;
      TelephonyAPI.leave.mockResolvedValue(
        joinedCall({ state_version: 4, participants: [] })
      );

      await store.leaveCall();

      expect(TelephonyAPI.leave).toHaveBeenCalledWith('call-1');
      expect(store.activeCall).toBeNull();
      expect(store.hasActiveCall).toBe(false);
      expect(store.lastEndedCall).toMatchObject({
        id: 'call-1',
        state: TELEPHONY_STATES.ENDED,
        end_reason: 'left',
      });
      expect(store.audioConnected).toBe(false);
      expect(store.hasInvitation).toBe(false);
      expect(store.isMuted).toBe(false);
      expect(store.orphanAudio).toBe(false);
      expect(store.showWidget).toBe(true);
    });
  });

  describe('dropOrphanAudio', () => {
    it('closes the card once the orphaned SIP leg is gone', () => {
      store.applyCall(joinedCall({ state_version: 4, participants: [] }), ME);

      store.dropOrphanAudio();

      expect(store.activeCall).toBeNull();
      expect(store.lastEndedCall?.state).toBe(TELEPHONY_STATES.ENDED);
      expect(store.audioConnected).toBe(false);
      expect(store.hasOrphanAudio).toBe(false);
    });

    it('is a no-op without orphaned audio', () => {
      store.dropOrphanAudio();

      expect(store.activeCall).not.toBeNull();
      expect(store.audioConnected).toBe(true);
    });
  });

  describe('calls routed by FreePBX', () => {
    const observed = (overrides = {}) =>
      joinedCall({
        source: 'pbx',
        user_id: ME,
        participants: [],
        ...overrides,
      });

    it('never asks to reconnect audio for them (FreePBX decides who rings)', () => {
      store.audioConnected = false;
      store.activeCall = observed();
      expect(store.needsReinvite).toBe(false);

      store.activeCall = observed({ source: 'controller' });
      expect(store.needsReinvite).toBe(true);
    });

    it('treats a FreePBX leg as incoming before the controller announces the call', () => {
      store.activeCall = null;
      store.audioConnected = false;
      store.hasInvitation = true;
      store.setPbxSession({ remote_number: '0987654321', answered: false });

      expect(store.isIncoming).toBe(true);
      expect(store.isPbxCall).toBe(true);
      expect(store.showWidget).toBe(true);

      store.setPbxSession({ answered: true, on_hold: true });
      store.hasInvitation = false;
      store.audioConnected = true;
      expect(store.isIncoming).toBe(false);
      expect(store.isOnHold).toBe(true);
      expect(store.pbxSession.remote_number).toBe('0987654321');
    });

    it('keeps SIP controls for a FreePBX leg instead of calling it orphaned audio', () => {
      store.activeCall = null;
      store.setPbxSession({ answered: true });

      expect(store.hasOrphanAudio).toBe(false);
      store.setPbxSession(null);
      expect(store.hasOrphanAudio).toBe(true);
    });
  });

  describe('FreePBX call handed over by this agent (REFER)', () => {
    const pbx = (overrides = {}) =>
      joinedCall({
        source: 'pbx',
        user_id: ME,
        participants: [],
        ...overrides,
      });

    beforeEach(() => {
      store.activeCall = pbx();
      store.audioConnected = false;
    });

    it('closes the card as transferred while the call has no owner yet', () => {
      store.applyCall(
        pbx({
          state: TELEPHONY_STATES.AGENT_CONNECTING,
          state_version: 4,
          user_id: null,
          previous_user_id: ME,
          ringing_user_ids: [OWNER],
        }),
        ME
      );

      expect(store.activeCall).toBeNull();
      expect(store.lastEndedCall).toMatchObject({ end_reason: 'transferred' });
    });

    it('shows the real end when the caller hung up before anyone else answered', () => {
      store.applyCall(
        pbx({
          state: TELEPHONY_STATES.ENDED,
          state_version: 4,
          user_id: null,
          previous_user_id: ME,
          end_reason: 'completed',
        }),
        ME
      );

      expect(store.lastEndedCall).toMatchObject({ end_reason: 'completed' });
    });
  });
});
