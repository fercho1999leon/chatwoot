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
  STANDBY: 'standby', // another tab of this agent holds the registration
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
    currentUserId: null,
    hasInvitation: false, // agent leg ringing in the browser: show "Connect audio"
    autoAcceptInvitation: false, // agent already pressed Answer: accept the next INVITE without asking
    audioConnected: false,
    // SIP audio still up in this tab although the controller no longer lists us on the call
    // (participant dropped from the snapshot, lost event…): keep the card so Hang up is reachable.
    orphanAudio: false,
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
    needsReinvite() {
      return (
        !!this.activeCall &&
        this.activeCall.state !== TELEPHONY_STATES.ENDED &&
        !this.hasInvitation &&
        !this.audioConnected &&
        !this.isIncoming
      );
    },
    isMissedInbound: state =>
      !state.activeCall &&
      state.lastEndedCall?.direction === 'inbound' &&
      !state.lastEndedCall?.answered_at,
    // A call ringing this agent: inbound from a customer, an internal call, or an invitation to join.
    // The callee of an internal call is "incoming" from creation (the caller's audio is still connecting).
    isIncoming() {
      const call = this.activeCall;
      if (!call || call.state === TELEPHONY_STATES.ENDED) return false;
      if (call.user_id === this.currentUserId) return false;
      if ((call.participants || []).includes(this.currentUserId)) return false;
      if (this.isInternalPeer) return call.state !== TELEPHONY_STATES.ANSWERED;
      return (call.ringing_user_ids || []).includes(this.currentUserId);
    },
    // This agent joined someone else's call (conference)
    isParticipant: state =>
      !!state.activeCall &&
      state.activeCall.user_id !== state.currentUserId &&
      (state.activeCall.participants || []).includes(state.currentUserId),
    isOwner: state =>
      !!state.activeCall && state.activeCall.user_id === state.currentUserId,
    // Audio without a call to control it: the widget offers Hang up only.
    hasOrphanAudio() {
      return this.audioConnected && (!this.hasActiveCall || this.orphanAudio);
    },
    // Callee of an internal call: a peer (can hang up), not a conference participant
    isInternalPeer: state =>
      !!state.activeCall &&
      state.activeCall.direction === 'internal' &&
      state.activeCall.to_user_id === state.currentUserId,
    showWidget() {
      return (
        this.hasActiveCall ||
        this.hasInvitation ||
        this.audioConnected ||
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
      if (currentUserId) this.currentUserId = currentUserId;
      const me = currentUserId || this.currentUserId;
      let involved = true;
      if (me) {
        const ringingMe = (call.ringing_user_ids || []).includes(me);
        const participant = (call.participants || []).includes(me);
        const mine = call.user_id === me;
        const transferTarget = call.transfer_to_user_id === me;
        const internalPeer =
          call.direction === 'internal' && call.to_user_id === me;
        const wasMine = this.activeCall?.id === call.id;
        involved =
          mine || ringingMe || participant || transferTarget || internalPeer;
        // Someone else answered / I left the conference / this step stopped ringing me: drop it silently.
        if (!involved && wasMine && call.state !== TELEPHONY_STATES.ENDED) {
          if (call.transfer_state !== 'completed') {
            // The SIP leg is still up in this tab: never leave audio without a Hang up button.
            if (this.audioConnected) {
              this.orphanAudio = true;
              if (
                (call.state_version ?? 0) > (this.activeCall.state_version ?? 0)
              )
                this.activeCall = call;
              return;
            }
            this.activeCall = null;
            this.hasInvitation = false;
            this.audioConnected = false;
            return;
          }
        }
        if (!involved && !wasMine) return; // not for this agent
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
        this.orphanAudio = false;
        this.idempotencyKey = null;
        return;
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
        this.orphanAudio = false;
        this.idempotencyKey = null;
        this.autoAcceptInvitation = false;
        return;
      }
      this.lastEndedCall = null;
      // A fresh call, or one we are involved in again: the audio is no longer orphaned.
      if (involved || !current || current.id !== call.id)
        this.orphanAudio = false;
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
      if (call) {
        this.applyCall(call);
        return;
      }
      if (!this.activeCall) return;
      // `active` may not list this tab's leg (participant not yet indexed, stale
      // snapshot) while the SIP session is up: trust the call itself before ending.
      if (this.audioConnected || this.hasInvitation) {
        let snapshot = null;
        try {
          snapshot = await TelephonyAPI.show(this.activeCall.id);
        } catch (error) {
          if (error?.response?.status !== 404) return; // transient: keep the card
        }
        if (snapshot?.id && snapshot.state !== TELEPHONY_STATES.ENDED) {
          this.applyCall(snapshot);
          return;
        }
      }
      this.applyCall({
        ...this.activeCall,
        state: TELEPHONY_STATES.ENDED,
        state_version: 1e9,
      });
    },

    async callAgent(toUserId) {
      this.autoAcceptInvitation = true;
      try {
        const call = await TelephonyAPI.createInternal(toUserId);
        this.applyCall(call, this.currentUserId);
        return call;
      } catch (error) {
        this.autoAcceptInvitation = false;
        throw error;
      }
    },

    // Owner adds a colleague to the call (conference); admins can also join themselves.
    async addAgent(userId) {
      if (!this.activeCall) return;
      const call = await TelephonyAPI.join(this.activeCall.id, userId);
      this.applyCall(call, this.currentUserId);
    },

    async joinCall(callId) {
      this.autoAcceptInvitation = true;
      try {
        const call = await TelephonyAPI.join(callId);
        this.applyCall(call, this.currentUserId);
      } catch (error) {
        this.autoAcceptInvitation = false;
        throw error;
      }
    },

    async leaveCall() {
      if (!this.activeCall) return;
      const call = this.activeCall;
      const snapshot = await TelephonyAPI.leave(call.id);
      if (snapshot?.id) this.applyCall(snapshot); // bookkeeping (versions, ended calls)
      // Closing card for the agent who left; the call itself goes on without them.
      this.lastEndedCall = {
        ...(snapshot?.id ? snapshot : call),
        state: TELEPHONY_STATES.ENDED,
        end_reason: 'left',
      };
      this.activeCall = null;
      this.hasInvitation = false;
      this.audioConnected = false;
      this.isMuted = false;
      this.orphanAudio = false;
      this.autoAcceptInvitation = false;
    },

    // Audio needed but no SIP invitation (page reload / network drop): ask the PBX to invite us again.
    async reinvite() {
      if (!this.activeCall) return;
      this.autoAcceptInvitation = true;
      // Internal callee before the PBX rings them (caller still connecting): the INVITE is on its way.
      if (
        this.isInternalPeer &&
        [
          TELEPHONY_STATES.REQUESTED,
          TELEPHONY_STATES.AGENT_CONNECTING,
        ].includes(this.activeCall.state)
      )
        return;
      try {
        const call = await TelephonyAPI.answer(this.activeCall.id);
        this.applyCall(call);
      } catch (error) {
        this.autoAcceptInvitation = false;
        throw error;
      }
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

    // Orphaned audio is gone (agent hung up locally or the PBX sent BYE): close the card.
    dropOrphanAudio() {
      if (!this.orphanAudio) return;
      if (this.activeCall)
        this.lastEndedCall = {
          ...this.activeCall,
          state: TELEPHONY_STATES.ENDED,
        };
      this.activeCall = null;
      this.orphanAudio = false;
      this.hasInvitation = false;
      this.audioConnected = false;
      this.isMuted = false;
    },

    setSipStatus(status, error = null) {
      this.sipStatus = status;
      this.sipError = error;
    },
  },
});
