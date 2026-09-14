import { defineStore } from 'pinia';
import TelephonyAPI from 'dashboard/api/telephony';

export const TELEPHONY_STATES = {
  REQUESTED: 'requested',
  AGENT_CONNECTING: 'agent_connecting',
  DIALING: 'dialing',
  RINGING: 'ringing',
  ANSWERED: 'answered',
  ENDED: 'ended',
};

// SIP session (browser ↔ PBX) is separate from the call (controller ↔ Asterisk).
export const SIP_STATUS = {
  IDLE: 'idle',
  CONNECTING: 'connecting',
  REGISTERED: 'registered',
  FAILED: 'failed',
};

const uuid = () =>
  globalThis.crypto?.randomUUID?.() ||
  `${Date.now()}-${Math.random().toString(16).slice(2)}`;

export const useTelephonyStore = defineStore('telephony', {
  state: () => ({
    // Per-conversation capabilities cache: { [displayId]: { enabled, can_call, reason, ... } }
    capabilities: {},
    activeCall: null, // { id, state, state_version, end_reason, conversation_display_id, ... }
    lastEndedCall: null,
    sipStatus: SIP_STATUS.IDLE,
    sipError: null,
    hasInvitation: false, // agent leg ringing in the browser: show "Connect audio"
    autoAcceptInvitation: false, // agent already pressed Answer: accept the next INVITE without asking
    audioConnected: false,
    isMuted: false,
    isCreating: false,
    idempotencyKey: null,
  }),

  getters: {
    hasActiveCall: state =>
      !!state.activeCall && state.activeCall.state !== TELEPHONY_STATES.ENDED,
    isAnswered: state => state.activeCall?.state === TELEPHONY_STATES.ANSWERED,
    isOnHold: state => !!state.activeCall?.on_hold,
    isTransferring: state => state.activeCall?.transfer_state === 'ringing',
    // Inbound call that ended without this agent (or anyone) answering it
    // Live call but this tab has no SIP leg (page reload / network drop)
    needsReinvite: state =>
      !!state.activeCall &&
      state.activeCall.state !== TELEPHONY_STATES.ENDED &&
      !state.hasInvitation &&
      !state.audioConnected,
    isMissedInbound: state =>
      !state.activeCall &&
      state.lastEndedCall?.direction === 'inbound' &&
      !state.lastEndedCall?.answered_at,
    // Inbound call ringing this agent (nobody has answered yet)
    isIncoming: state =>
      state.activeCall?.direction === 'inbound' &&
      !state.activeCall?.user_id &&
      state.activeCall?.state !== TELEPHONY_STATES.ENDED,
    showWidget() {
      return (
        this.hasActiveCall ||
        this.hasInvitation ||
        this.sipStatus === SIP_STATUS.CONNECTING ||
        this.sipStatus === SIP_STATUS.FAILED ||
        !!this.lastEndedCall
      );
    },
    canCall: state => displayId =>
      !!state.capabilities[displayId]?.can_call &&
      !(state.activeCall && state.activeCall.state !== TELEPHONY_STATES.ENDED),
  },

  actions: {
    async fetchCapabilities(displayId) {
      try {
        const caps = await TelephonyAPI.capabilities(displayId);
        this.capabilities[displayId] = caps;
        if (caps.active_call) this.applyCall(caps.active_call);
        return caps;
      } catch (error) {
        this.capabilities[displayId] = { enabled: false, can_call: false };
        return this.capabilities[displayId];
      }
    },

    // Apply a snapshot/event. Only monotonically increasing versions win.
    // `currentUserId` lets a tab drop a call that was transferred away from it.
    applyCall(call, currentUserId = null) {
      if (!call?.id) return;
      if (call.direction === 'inbound' && currentUserId) {
        const ringingMe = (call.ringing_user_ids || []).includes(currentUserId);
        const mine = call.user_id === currentUserId;
        const wasMine = this.activeCall?.id === call.id;
        // Someone else answered, or this step stopped ringing me: drop it silently.
        if (
          !ringingMe &&
          !mine &&
          wasMine &&
          call.state !== TELEPHONY_STATES.ENDED
        ) {
          this.activeCall = null;
          this.hasInvitation = false;
          return;
        }
        if (!ringingMe && !mine && !wasMine) return; // not for this agent
        if (call.state === TELEPHONY_STATES.ENDED && !wasMine) return;
      }
      if (
        currentUserId &&
        call.user_id &&
        call.user_id !== currentUserId &&
        call.transfer_state === 'completed' &&
        this.activeCall?.id === call.id
      ) {
        this.lastEndedCall = {
          ...call,
          state: TELEPHONY_STATES.ENDED,
          end_reason: 'transferred',
        };
        this.activeCall = null;
        this.hasInvitation = false;
        this.audioConnected = false;
        this.isMuted = false;
        this.idempotencyKey = null;
        return;
      }
      if (
        currentUserId &&
        call.user_id &&
        call.user_id !== currentUserId &&
        call.transfer_to_user_id !== currentUserId
      ) {
        return; // event for another agent (broadcast to previous owner after completion)
      }
      const current = this.activeCall;
      if (
        current &&
        current.id === call.id &&
        (call.state_version ?? 0) <= (current.state_version ?? 0)
      ) {
        return;
      }
      if (
        current &&
        current.id !== call.id &&
        call.state === TELEPHONY_STATES.ENDED
      ) {
        return; // late event for an older call
      }
      if (call.state === TELEPHONY_STATES.ENDED) {
        this.lastEndedCall = call;
        this.activeCall = null;
        this.hasInvitation = false;
        this.audioConnected = false;
        this.isMuted = false;
        this.idempotencyKey = null;
        this.autoAcceptInvitation = false;
        return;
      }
      this.lastEndedCall = null;
      this.activeCall = call;
    },

    async createCall(displayId) {
      if (this.isCreating) return null;
      this.isCreating = true;
      // One key per attempt; a retry (double click / timeout) reuses it.
      this.idempotencyKey = this.idempotencyKey || uuid();
      try {
        const call = await TelephonyAPI.createCall(
          displayId,
          this.idempotencyKey
        );
        this.applyCall(call);
        return call;
      } finally {
        this.isCreating = false;
      }
    },

    async refreshActive() {
      const call = await TelephonyAPI.activeCall();
      if (call) this.applyCall(call);
      else if (this.activeCall)
        this.applyCall({
          ...this.activeCall,
          state: TELEPHONY_STATES.ENDED,
          state_version: 1e9,
        });
    },

    // Audio needed but no SIP invitation (page reload / network drop): ask the PBX to invite us again.
    async reinvite() {
      if (!this.activeCall) return;
      this.autoAcceptInvitation = true;
      const call = await TelephonyAPI.answer(this.activeCall.id);
      this.applyCall(call);
    },

    async hangup() {
      if (!this.activeCall) return;
      const call = await TelephonyAPI.hangup(this.activeCall.id);
      this.applyCall(call);
    },

    async sendDtmf(digits) {
      if (!this.activeCall) return;
      await TelephonyAPI.dtmf(this.activeCall.id, digits);
    },

    async toggleHold() {
      if (!this.activeCall) return;
      const call = this.activeCall.on_hold
        ? await TelephonyAPI.unhold(this.activeCall.id)
        : await TelephonyAPI.hold(this.activeCall.id);
      this.applyCall(call);
    },

    async transferTo(userId) {
      if (!this.activeCall) return;
      const call = await TelephonyAPI.transfer(this.activeCall.id, userId);
      this.applyCall(call);
    },

    async cancelTransfer() {
      if (!this.activeCall) return;
      const call = await TelephonyAPI.cancelTransfer(this.activeCall.id);
      this.applyCall(call);
    },

    dismissEnded() {
      this.lastEndedCall = null;
    },

    setSipStatus(status, error = null) {
      this.sipStatus = status;
      this.sipError = error;
    },
  },
});
