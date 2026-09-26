<script setup>
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import {
  useTelephonyStore,
  TELEPHONY_STATES,
  SIP_STATUS,
} from 'dashboard/stores/telephony';
import { useSipSession } from 'dashboard/composables/useSipSession';
import { useRingtone } from 'dashboard/composables/useRingtone';
import { useCallNotification } from 'dashboard/composables/useCallNotification';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TelephonyAPI from 'dashboard/api/telephony';

const { t } = useI18n();
const router = useRouter();
const vuexStore = useStore();
const store = useTelephonyStore();
const { accountId } = useAccount();
const {
  acceptInvitation,
  setMuted,
  hangupLocal,
  connect,
  setHold,
  sendDtmf,
  transfer: referTo,
} = useSipSession();
const ringtone = useRingtone();
const callNotification = useCallNotification();

const DTMF_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
const showKeypad = ref(false);
const showTransfer = ref(false);
const pickerMode = ref('transfer'); // 'transfer' | 'add'
const transferAgents = ref([]);
const transferInboxId = ref(null);
const canAddMembers = ref(false);
const transferLoading = ref(false);
const addingMember = ref(null);
const isWorking = ref(false);
const seconds = ref(0);
// Transfer of a FreePBX-routed call (REFER): extensions, queues and ring groups of the PBX, or any number.
const pbxTargets = ref({ extensions: [], queues: [], ringgroups: [] });
const pbxTransferNumber = ref('');
const pbxTargetGroups = computed(() => [
  { key: 'queues', label: t('TELEPHONY.WIDGET.PBX_QUEUES') },
  { key: 'ringgroups', label: t('TELEPHONY.WIDGET.PBX_RING_GROUPS') },
  { key: 'extensions', label: t('TELEPHONY.WIDGET.PBX_EXTENSIONS') },
]);
let timer = null;

const call = computed(() => store.activeCall || store.lastEndedCall);
const state = computed(() => call.value?.state);
// Another tab of this agent holds the softphone: audio buttons here would ring that tab.
const isStandby = computed(() => store.sipStatus === SIP_STATUS.STANDBY);
// Mute/keypad/hold/transfer only make sense with audio up; while reconnecting the row shows Reconnect.
// A FreePBX-routed leg in this tab: its controls are SIP (hold, REFER, DTMF), not the controller API.
const isPbx = computed(() => store.isPbxCall);
const hasAudioControls = computed(
  () =>
    (store.isAnswered || isPbx.value) &&
    store.audioConnected &&
    !isStandby.value
);
// Keypad, hold and transfer: the owner of a controller call, or whoever holds a FreePBX leg.
const canControl = computed(
  () => hasAudioControls.value && (store.isOwner || isPbx.value)
);
// A SIP leg is up or ringing in this tab: Hang up must always be reachable.
const sessionLive = computed(() => store.audioConnected || store.hasInvitation);

const isInternal = computed(() => call.value?.direction === 'internal');
// Names of the other people on the call (owner + participants, minus me)
const agentNames = computed(() => {
  const names = [];
  if (!store.isOwner && call.value?.owner_name)
    names.push(call.value.owner_name);
  (call.value?.participant_names || []).forEach(n => names.push(n));
  if (isInternal.value && store.isOwner && call.value?.to_user_name)
    names.push(call.value.to_user_name);
  return names.join(', ');
});

const title = computed(() => {
  if (store.hasOrphanAudio) return t('TELEPHONY.WIDGET.ORPHAN_AUDIO');
  if (
    state.value === TELEPHONY_STATES.ENDED &&
    call.value?.end_reason === 'left'
  )
    return t('TELEPHONY.WIDGET.LEFT_CALL');
  if (store.isIncoming && store.isAnswered)
    return t('TELEPHONY.WIDGET.JOIN_INVITE');
  if (store.isIncoming)
    return isInternal.value
      ? t('TELEPHONY.WIDGET.INTERNAL_INCOMING')
      : t('TELEPHONY.WIDGET.INCOMING');
  if (store.isParticipant) return t('TELEPHONY.WIDGET.JOINED');
  if (store.isMissedInbound) return t('TELEPHONY.WIDGET.MISSED');
  if (store.isTransferring) return t('TELEPHONY.WIDGET.TRANSFERRING');
  if (store.isOnHold && store.isAnswered) return t('TELEPHONY.WIDGET.ON_HOLD');
  if (store.sipStatus === SIP_STATUS.FAILED)
    return t('TELEPHONY.WIDGET.SIP_FAILED');
  if (store.sipStatus === SIP_STATUS.CONNECTING)
    return t('TELEPHONY.WIDGET.SIP_CONNECTING');
  if (store.hasInvitation) return t('TELEPHONY.WIDGET.INVITATION');
  if (!state.value && isPbx.value)
    return store.isOnHold
      ? t('TELEPHONY.WIDGET.ON_HOLD')
      : t('TELEPHONY.STATE.ANSWERED');
  if (!state.value) return '';
  return t(`TELEPHONY.STATE.${state.value.toUpperCase()}`);
});

const pbxCaller = computed(() =>
  [store.pbxSession?.remote_name, store.pbxSession?.remote_number]
    .filter(Boolean)
    .filter((v, i, all) => all.indexOf(v) === i)
    .join(' · ')
);

const subtitle = computed(() => {
  // FreePBX rang us before (or without) the controller announcing the call: show who is calling.
  if (!call.value && isPbx.value) return pbxCaller.value;
  if (store.isMissedInbound) {
    return [call.value?.contact_name, call.value?.destination_masked]
      .filter(Boolean)
      .join(' · ');
  }
  if (state.value === TELEPHONY_STATES.ENDED && call.value?.end_reason) {
    return t(
      `TELEPHONY.END_REASON.${call.value.end_reason.toUpperCase()}`,
      call.value.end_reason
    );
  }
  if (store.sipStatus === SIP_STATUS.FAILED && store.sipError) {
    return t(
      `TELEPHONY.ERROR.${String(store.sipError).toUpperCase()}`,
      store.sipError
    );
  }
  if (isStandby.value) return t('TELEPHONY.WIDGET.SIP_STANDBY');
  if (isInternal.value) {
    return store.isOwner
      ? t('TELEPHONY.WIDGET.CALLING_AGENT', { name: agentNames.value })
      : call.value?.contact_name || '';
  }
  if (store.isParticipant || (store.isIncoming && store.isAnswered))
    return t('TELEPHONY.WIDGET.WITH', { names: agentNames.value });
  const base =
    call.value?.direction === 'inbound' && call.value?.contact_name
      ? `${call.value.contact_name} · ${call.value.destination_masked}`
      : call.value?.destination_masked || '';
  const others = call.value?.participant_names || [];
  const parts = [others.length ? `${base} · +${others.join(', ')}` : base];
  if (call.value?.peer_on_hold && store.isAnswered)
    parts.unshift(t('TELEPHONY.WIDGET.PEER_ON_HOLD'));
  if (call.value?.routed_by === 'bot')
    parts.push(t('TELEPHONY.WIDGET.ROUTED_BY_BOT'));
  return parts.filter(Boolean).join(' · ');
});

const formattedDuration = computed(() => {
  const total =
    state.value === TELEPHONY_STATES.ENDED
      ? call.value?.duration_seconds || 0
      : seconds.value;
  const m = String(Math.floor(total / 60)).padStart(2, '0');
  const s = String(total % 60).padStart(2, '0');
  return `${m}:${s}`;
});

const stopTimer = () => {
  if (timer) clearInterval(timer);
  timer = null;
};
const startTimer = () => {
  stopTimer();
  const from = call.value?.answered_at
    ? new Date(call.value.answered_at)
    : new Date();
  const tick = () => {
    seconds.value = Math.max(
      0,
      Math.round((Date.now() - from.getTime()) / 1000)
    );
  };
  tick();
  timer = setInterval(tick, 1000);
};

watch(state, s => {
  if (s === TELEPHONY_STATES.ANSWERED) startTimer();
  else if (s === TELEPHONY_STATES.ENDED || !s) {
    stopTimer();
    if (!s) seconds.value = 0;
  }
});

// Ring while an incoming call is offered to this agent; stop on answer/decline/end.
watch(
  () => store.isIncoming && store.hasInvitation,
  ringing => (ringing ? ringtone.start() : ringtone.stop()),
  { immediate: true }
);
// Safety net for lost ActionCable events: re-read the active call while one is live.
const ACTIVE_POLL_MS = 15000;
let pollTimer = null;
watch(
  () => store.hasActiveCall,
  live => {
    clearInterval(pollTimer);
    if (!live) return;
    pollTimer = setInterval(() => {
      store.refreshActive().catch(() => {});
    }, ACTIVE_POLL_MS);
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  clearInterval(pollTimer);
  ringtone.stop();
  callNotification.clear();
});

const onAccept = async () => {
  isWorking.value = true;
  try {
    if (!store.hasInvitation) {
      await store.reinvite(); // the INVITE arrives again and is auto-accepted
    } else {
      await acceptInvitation();
    }
  } catch (error) {
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isWorking.value = false;
  }
};

// Decline an incoming call: only reject the SIP invitation; the PBX moves on to the next destination.
const onDecline = () => {
  hangupLocal();
  store.activeCall = null;
};

// Tell the controller first (it hangs up every leg and ends the call), then drop the local
// SIP leg no matter what: a BYE sent before the API call reaches Asterisk first and the
// controller would log an `agent_dropped` (30 s grace + hold music) for a deliberate hangup.
// Orphaned audio has no call to act on and just closes the card.
const onHangup = async () => {
  // FreePBX-routed leg: a local BYE is the hang up; the controller sees the leg go down.
  if (isPbx.value) {
    hangupLocal();
    return;
  }
  isWorking.value = true;
  const orphan = store.hasOrphanAudio;
  // Never leave the agent listening while a slow controller answers: local BYE after 1.5 s at most.
  const localFallback = setTimeout(hangupLocal, 1500);
  try {
    if (orphan || !store.hasActiveCall) store.dropOrphanAudio();
    else if (store.isParticipant) await store.leaveCall();
    else await store.hangup();
  } catch (e) {
    // the controller will close it on StasisEnd anyway
  } finally {
    clearTimeout(localFallback);
    hangupLocal(); // idempotent: usually already terminated by the controller's hangup
    isWorking.value = false;
  }
};

const onToggleMute = () => setMuted(!store.isMuted);

const onToggleHold = async () => {
  isWorking.value = true;
  try {
    if (isPbx.value) await setHold(!store.isOnHold);
    else await store.toggleHold();
  } catch (e) {
    // 409 si no está contestada
  } finally {
    isWorking.value = false;
  }
};

const openTransfer = async (mode = 'transfer') => {
  const reopen = !showTransfer.value || pickerMode.value !== mode;
  pickerMode.value = mode;
  showTransfer.value = reopen;
  if (!showTransfer.value) return;
  transferLoading.value = true;
  if (isPbx.value) {
    try {
      pbxTargets.value = await TelephonyAPI.transferTargets();
    } catch (e) {
      pbxTargets.value = { extensions: [], queues: [], ringgroups: [] };
    } finally {
      transferLoading.value = false;
    }
    return;
  }
  try {
    const data = await TelephonyAPI.agents(call.value?.conversation_display_id);
    transferAgents.value = data.agents;
    transferInboxId.value = data.inbox_id;
    canAddMembers.value = data.can_add_members;
  } catch (e) {
    transferAgents.value = [];
  } finally {
    transferLoading.value = false;
  }
};

// Admin shortcut: make the agent a collaborator of the inbox so the transfer can proceed.
const onAddToInbox = async agent => {
  addingMember.value = agent.user_id;
  try {
    const members = await vuexStore.dispatch('inboxMembers/get', {
      inboxId: transferInboxId.value,
    });
    const agentList = [...members.data.payload.map(m => m.id), agent.user_id];
    await vuexStore.dispatch('inboxMembers/create', {
      inboxId: transferInboxId.value,
      agentList,
    });
    agent.inbox_member = true;
  } catch (error) {
    useAlert(t('TELEPHONY.ERROR.UNKNOWN'));
  } finally {
    addingMember.value = null;
  }
};

const onAddAgent = async userId => {
  isWorking.value = true;
  try {
    await store.addAgent(userId);
    showTransfer.value = false;
  } catch (error) {
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isWorking.value = false;
  }
};

const onLeave = async () => {
  isWorking.value = true;
  try {
    hangupLocal();
    await store.leaveCall();
  } catch (e) {
    // the leg is already gone; the controller drops us from the bridge
  } finally {
    isWorking.value = false;
  }
};

const onTransfer = async userId => {
  isWorking.value = true;
  try {
    await store.transferTo(userId);
    showTransfer.value = false;
  } catch (error) {
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isWorking.value = false;
  }
};

// Blind transfer of a FreePBX-routed call: FreePBX takes it to the target and hangs up our leg.
const onPbxTransfer = async number => {
  if (!number) return;
  isWorking.value = true;
  try {
    await referTo(number);
    showTransfer.value = false;
    pbxTransferNumber.value = '';
  } catch (error) {
    useAlert(t('TELEPHONY.ERROR.TRANSFER_FAILED'));
  } finally {
    isWorking.value = false;
  }
};

const onPick = userId =>
  pickerMode.value === 'add' ? onAddAgent(userId) : onTransfer(userId);

const onCancelTransfer = async () => {
  isWorking.value = true;
  try {
    await store.cancelTransfer();
  } finally {
    isWorking.value = false;
  }
};

// Digits sent in this call: the agent sees what reached the line (RFC 4733 gives no audible feedback).
const dtmfSent = ref('');
const DTMF_ECHO_MAX = 24;
watch(
  () => call.value?.id,
  () => {
    dtmfSent.value = '';
  }
);

const onDtmf = async digit => {
  try {
    if (isPbx.value) {
      if (!sendDtmf(digit)) throw new Error('dtmf_not_sent');
    } else await store.sendDtmf(digit);
    dtmfSent.value = (dtmfSent.value + digit).slice(-DTMF_ECHO_MAX);
  } catch (e) {
    useAlert(t('TELEPHONY.ERROR.DTMF_FAILED'));
  }
};

// The X never leaves audio behind: hang up the SIP leg if one is still live.
const onDismiss = () => {
  if (sessionLive.value) hangupLocal();
  store.dropOrphanAudio();
  store.dismissEnded();
  if (store.sipStatus === SIP_STATUS.FAILED)
    store.setSipStatus(SIP_STATUS.IDLE);
};

const onRetryRegister = () => connect({ force: true });

// Missed inbound: call the contact back from the same conversation.
const onCallBack = async () => {
  const displayId = call.value?.conversation_display_id;
  if (!displayId) return;
  isWorking.value = true;
  try {
    store.dismissEnded();
    await store.createCall(displayId);
  } catch (error) {
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isWorking.value = false;
  }
};

const goToConversation = () => {
  if (!call.value?.conversation_display_id) return;
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: accountId.value,
      conversation_id: call.value.conversation_display_id,
    },
  });
};

// Desktop notification + blinking title as soon as the call is offered (even before the INVITE).
watch(
  () => store.isIncoming,
  incoming => {
    if (!incoming) {
      callNotification.clear();
      return;
    }
    callNotification.notify({
      title: title.value,
      body: subtitle.value,
      onClick: goToConversation,
    });
  },
  { immediate: true }
);

// After a reload/reconnect, the call may still be live on the controller.
onMounted(() => {
  if (store.hasActiveCall && state.value === TELEPHONY_STATES.ANSWERED)
    startTimer();
});
onBeforeUnmount(stopTimer);
</script>

<template>
  <div
    v-if="store.showWidget"
    class="fixed ltr:right-4 rtl:left-4 bottom-4 z-50 w-[320px] rounded-xl border border-n-weak bg-n-solid-2 shadow-lg p-4 flex flex-col gap-3"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <p class="text-sm font-medium text-n-slate-12 truncate">{{ title }}</p>
        <p class="text-xs text-n-slate-11 truncate">{{ subtitle }}</p>
      </div>
      <span
        v-if="state === 'answered' || state === 'ended'"
        class="text-xs tabular-nums text-n-slate-11"
      >
        {{ formattedDuration }}
      </span>
    </div>

    <div
      v-if="showTransfer && isPbx && hasAudioControls"
      class="flex flex-col gap-1 max-h-64 overflow-y-auto"
    >
      <p class="text-xs text-n-slate-11">
        {{ t('TELEPHONY.WIDGET.TRANSFER_TO') }}
      </p>
      <form
        class="flex items-center gap-1"
        @submit.prevent="onPbxTransfer(pbxTransferNumber)"
      >
        <Input
          v-model="pbxTransferNumber"
          size="sm"
          class="flex-1"
          :placeholder="t('TELEPHONY.WIDGET.PBX_TRANSFER_NUMBER')"
        />
        <NextButton
          sm
          solid
          blue
          type="submit"
          icon="i-lucide-phone-forwarded"
          :disabled="!pbxTransferNumber"
          :is-loading="isWorking"
        />
      </form>
      <p v-if="transferLoading" class="text-xs text-n-slate-11">
        {{ t('TELEPHONY.WIDGET.LOADING') }}
      </p>
      <template v-else>
        <template v-for="group in pbxTargetGroups" :key="group.key">
          <template v-if="pbxTargets[group.key]?.length">
            <p class="text-xs font-medium text-n-slate-11 mt-1">
              {{ group.label }}
            </p>
            <NextButton
              v-for="target in pbxTargets[group.key]"
              :key="`${group.key}-${target.number}`"
              sm
              faded
              slate
              class="w-full"
              :label="`${target.name || target.number} (${target.number})`"
              @click="onPbxTransfer(target.number)"
            />
          </template>
        </template>
      </template>
    </div>

    <div
      v-if="showTransfer && store.isAnswered && !isPbx"
      class="flex flex-col gap-1"
    >
      <p class="text-xs text-n-slate-11">
        {{
          pickerMode === 'add'
            ? t('TELEPHONY.WIDGET.ADD_AGENT_TO')
            : t('TELEPHONY.WIDGET.TRANSFER_TO')
        }}
      </p>
      <p v-if="transferLoading" class="text-xs text-n-slate-11">
        {{ t('TELEPHONY.WIDGET.LOADING') }}
      </p>
      <p v-else-if="!transferAgents.length" class="text-xs text-n-slate-11">
        {{ t('TELEPHONY.WIDGET.NO_AGENTS') }}
      </p>
      <div
        v-for="agent in transferAgents"
        :key="agent.user_id"
        class="flex items-center gap-1"
      >
        <span
          v-tooltip="
            agent.registered === false
              ? t('TELEPHONY.TRANSFER.NOT_REGISTERED')
              : null
          "
          class="flex-1 flex items-center gap-1.5 min-w-0"
        >
          <span
            v-if="agent.registered != null"
            class="size-2 rounded-full shrink-0"
            :class="agent.registered ? 'bg-n-teal-9' : 'bg-n-slate-8'"
          />
          <NextButton
            sm
            faded
            slate
            class="flex-1 min-w-0"
            :disabled="
              agent.busy ||
              agent.availability === 'offline' ||
              agent.registered === false ||
              !agent.inbox_member
            "
            :label="`${agent.name} (${agent.extension})${agent.busy ? ' · ' + t('TELEPHONY.WIDGET.BUSY') : ''}${!agent.inbox_member ? ' · ' + t('TELEPHONY.WIDGET.NOT_INBOX_MEMBER') : ''}`"
            @click="onPick(agent.user_id)"
          />
        </span>
        <NextButton
          v-if="!agent.inbox_member && canAddMembers"
          sm
          ghost
          blue
          :is-loading="addingMember === agent.user_id"
          :label="t('TELEPHONY.WIDGET.ADD_TO_INBOX')"
          @click="onAddToInbox(agent)"
        />
      </div>
    </div>

    <div
      v-if="store.isTransferring"
      class="flex items-center justify-between gap-2"
    >
      <span class="text-xs text-n-slate-11">{{
        t('TELEPHONY.WIDGET.TRANSFER_RINGING')
      }}</span>
      <NextButton
        sm
        ghost
        slate
        :label="t('TELEPHONY.WIDGET.CANCEL')"
        @click="onCancelTransfer"
      />
    </div>

    <p
      v-if="showKeypad && canControl && dtmfSent"
      class="text-sm text-center tabular-nums tracking-widest text-n-slate-12"
    >
      {{ dtmfSent }}
    </p>
    <div v-if="showKeypad && canControl" class="grid grid-cols-3 gap-1">
      <NextButton
        v-for="digit in DTMF_KEYS"
        :key="digit"
        sm
        faded
        slate
        :label="digit"
        @click="onDtmf(digit)"
      />
    </div>

    <div class="flex items-center justify-between gap-2">
      <NextButton
        v-if="call?.conversation_display_id"
        sm
        ghost
        slate
        icon="i-lucide-message-square"
        @click="goToConversation"
      />
      <div class="flex flex-wrap items-center justify-end gap-2 ml-auto">
        <NextButton
          v-if="store.sipStatus === SIP_STATUS.FAILED"
          sm
          solid
          blue
          :label="t('TELEPHONY.WIDGET.RETRY')"
          @click="onRetryRegister"
        />
        <NextButton
          v-if="isStandby"
          sm
          solid
          blue
          icon="i-lucide-monitor-check"
          :label="t('TELEPHONY.WIDGET.USE_THIS_TAB')"
          @click="onRetryRegister"
        />
        <NextButton
          v-if="!isStandby && (store.hasInvitation || store.needsReinvite)"
          sm
          solid
          teal
          icon="i-lucide-phone-incoming"
          :label="
            store.isIncoming
              ? t('TELEPHONY.WIDGET.ANSWER')
              : store.isAnswered
                ? t('TELEPHONY.WIDGET.RECONNECT_AUDIO')
                : t('TELEPHONY.WIDGET.CONNECT_AUDIO')
          "
          :is-loading="isWorking"
          @click="onAccept"
        />
        <NextButton
          v-if="store.isIncoming"
          sm
          faded
          ruby
          icon="i-lucide-phone-off"
          :label="t('TELEPHONY.WIDGET.DECLINE')"
          @click="onDecline"
        />
        <NextButton
          v-if="hasAudioControls"
          sm
          ghost
          slate
          :icon="store.isMuted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
          @click="onToggleMute"
        />
        <NextButton
          v-if="canControl"
          sm
          ghost
          slate
          icon="i-lucide-grid-3x3"
          @click="showKeypad = !showKeypad"
        />
        <NextButton
          v-if="canControl && !store.isTransferring"
          sm
          ghost
          slate
          :icon="store.isOnHold ? 'i-lucide-play' : 'i-lucide-pause'"
          :is-loading="isWorking"
          @click="onToggleHold"
        />
        <NextButton
          v-if="canControl && !store.isTransferring"
          v-tooltip="t('TELEPHONY.WIDGET.TRANSFER')"
          sm
          ghost
          slate
          icon="i-lucide-phone-forwarded"
          @click="openTransfer('transfer')"
        />
        <NextButton
          v-if="
            hasAudioControls && store.isOwner && !isPbx && !store.isTransferring
          "
          v-tooltip="t('TELEPHONY.WIDGET.ADD_AGENT')"
          sm
          ghost
          slate
          icon="i-lucide-user-plus"
          @click="openTransfer('add')"
        />
        <NextButton
          v-if="store.isParticipant"
          sm
          solid
          ruby
          icon="i-lucide-log-out"
          :label="t('TELEPHONY.WIDGET.LEAVE')"
          :is-loading="isWorking"
          @click="onLeave"
        />
        <NextButton
          v-if="
            (store.hasActiveCall || sessionLive || isPbx) &&
            !store.isIncoming &&
            !store.isParticipant
          "
          sm
          solid
          ruby
          icon="i-lucide-phone-off"
          :is-loading="isWorking"
          @click="onHangup"
        />
        <NextButton
          v-if="store.isMissedInbound"
          sm
          solid
          teal
          icon="i-lucide-phone-outgoing"
          :label="t('TELEPHONY.WIDGET.CALL_BACK')"
          :is-loading="isWorking"
          @click="onCallBack"
        />
        <NextButton
          v-if="!store.hasActiveCall && !store.hasInvitation"
          sm
          ghost
          slate
          icon="i-lucide-x"
          @click="onDismiss"
        />
      </div>
    </div>
  </div>
</template>
