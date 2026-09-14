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
import NextButton from 'dashboard/components-next/button/Button.vue';
import TelephonyAPI from 'dashboard/api/telephony';

const { t } = useI18n();
const router = useRouter();
const vuexStore = useStore();
const store = useTelephonyStore();
const { accountId } = useAccount();
const { acceptInvitation, setMuted, hangupLocal, connect } = useSipSession();
const ringtone = useRingtone();

const DTMF_KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
const showKeypad = ref(false);
const showTransfer = ref(false);
const transferAgents = ref([]);
const transferInboxId = ref(null);
const canAddMembers = ref(false);
const transferLoading = ref(false);
const addingMember = ref(null);
const isWorking = ref(false);
const seconds = ref(0);
let timer = null;

const call = computed(() => store.activeCall || store.lastEndedCall);
const state = computed(() => call.value?.state);

const title = computed(() => {
  if (store.isIncoming) return t('TELEPHONY.WIDGET.INCOMING');
  if (store.isMissedInbound) return t('TELEPHONY.WIDGET.MISSED');
  if (store.isTransferring) return t('TELEPHONY.WIDGET.TRANSFERRING');
  if (store.isOnHold && store.isAnswered) return t('TELEPHONY.WIDGET.ON_HOLD');
  if (store.sipStatus === SIP_STATUS.FAILED)
    return t('TELEPHONY.WIDGET.SIP_FAILED');
  if (store.sipStatus === SIP_STATUS.CONNECTING)
    return t('TELEPHONY.WIDGET.SIP_CONNECTING');
  if (store.hasInvitation) return t('TELEPHONY.WIDGET.INVITATION');
  if (!state.value) return '';
  return t(`TELEPHONY.STATE.${state.value.toUpperCase()}`);
});

const subtitle = computed(() => {
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
  if (call.value?.direction === 'inbound' && call.value?.contact_name)
    return `${call.value.contact_name} · ${call.value.destination_masked}`;
  return call.value?.destination_masked || '';
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
onBeforeUnmount(() => ringtone.stop());

const onAccept = async () => {
  isWorking.value = true;
  try {
    await acceptInvitation();
  } finally {
    isWorking.value = false;
  }
};

// Decline an incoming call: only reject the SIP invitation; the PBX moves on to the next destination.
const onDecline = () => {
  hangupLocal();
  store.activeCall = null;
};

const onHangup = async () => {
  isWorking.value = true;
  try {
    hangupLocal();
    if (store.hasActiveCall) await store.hangup();
  } catch (e) {
    // the controller will close it on StasisEnd anyway
  } finally {
    isWorking.value = false;
  }
};

const onToggleMute = () => setMuted(!store.isMuted);

const onToggleHold = async () => {
  isWorking.value = true;
  try {
    await store.toggleHold();
  } catch (e) {
    // 409 si no está contestada
  } finally {
    isWorking.value = false;
  }
};

const openTransfer = async () => {
  showTransfer.value = !showTransfer.value;
  if (!showTransfer.value) return;
  transferLoading.value = true;
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

const onCancelTransfer = async () => {
  isWorking.value = true;
  try {
    await store.cancelTransfer();
  } finally {
    isWorking.value = false;
  }
};

const onDtmf = async digit => {
  try {
    await store.sendDtmf(digit);
  } catch (e) {
    // 409 when not answered: keypad is only shown in answered state
  }
};

const onDismiss = () => {
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

    <div v-if="showTransfer && store.isAnswered" class="flex flex-col gap-1">
      <p class="text-xs text-n-slate-11">
        {{ t('TELEPHONY.WIDGET.TRANSFER_TO') }}
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
        <NextButton
          sm
          faded
          slate
          class="flex-1"
          :disabled="
            agent.busy ||
            agent.availability === 'offline' ||
            !agent.inbox_member
          "
          :label="`${agent.name} (${agent.extension})${agent.busy ? ' · ' + t('TELEPHONY.WIDGET.BUSY') : ''}${!agent.inbox_member ? ' · ' + t('TELEPHONY.WIDGET.NOT_INBOX_MEMBER') : ''}`"
          @click="onTransfer(agent.user_id)"
        />
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

    <div v-if="showKeypad && store.isAnswered" class="grid grid-cols-3 gap-1">
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
      <div class="flex items-center gap-2 ml-auto">
        <NextButton
          v-if="store.sipStatus === SIP_STATUS.FAILED"
          sm
          solid
          blue
          :label="t('TELEPHONY.WIDGET.RETRY')"
          @click="onRetryRegister"
        />
        <NextButton
          v-if="store.hasInvitation"
          sm
          solid
          teal
          icon="i-lucide-phone-incoming"
          :label="
            store.isIncoming
              ? t('TELEPHONY.WIDGET.ANSWER')
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
          v-if="store.isAnswered"
          sm
          ghost
          slate
          :icon="store.isMuted ? 'i-lucide-mic-off' : 'i-lucide-mic'"
          @click="onToggleMute"
        />
        <NextButton
          v-if="store.isAnswered"
          sm
          ghost
          slate
          icon="i-lucide-grid-3x3"
          @click="showKeypad = !showKeypad"
        />
        <NextButton
          v-if="store.isAnswered && !store.isTransferring"
          sm
          ghost
          slate
          :icon="store.isOnHold ? 'i-lucide-play' : 'i-lucide-pause'"
          :is-loading="isWorking"
          @click="onToggleHold"
        />
        <NextButton
          v-if="store.isAnswered && !store.isTransferring"
          sm
          ghost
          slate
          icon="i-lucide-phone-forwarded"
          @click="openTransfer"
        />
        <NextButton
          v-if="
            (store.hasActiveCall || store.hasInvitation) && !store.isIncoming
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
