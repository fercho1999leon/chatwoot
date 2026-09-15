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
});
