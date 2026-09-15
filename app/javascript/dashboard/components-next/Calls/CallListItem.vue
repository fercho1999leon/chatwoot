<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { relativeDayTimestamp } from 'shared/helpers/timeHelper';
import { getInboxVoiceIcon } from 'dashboard/helper/inbox';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import AudioPlayer from 'dashboard/components-next/audio/AudioPlayer.vue';
import {
  VOICE_CALL_DIRECTION,
  VOICE_CALL_STATUS,
} from 'dashboard/components-next/message/constants';
import CallStatusBadge from './CallStatusBadge.vue';
import { CALL_KIND, getCallKind } from './constants';

const props = defineProps({
  call: {
    type: Object,
    required: true,
  },
  canJoin: { type: Boolean, default: false },
});
const emit = defineEmits(['join']);

const { t } = useI18n();
const route = useRoute();

const kind = computed(() => getCallKind(props.call));

const isInternal = computed(() => props.call.direction === 'internal');

const contactName = computed(() => {
  if (isInternal.value)
    return t('CALLS_PAGE.ROW.INTERNAL_CALL', {
      name: props.call.toUser?.name || '',
    });
  if (!props.call.contact) return t('CALLS_PAGE.ROW.DELETED_CONTACT');
  return (
    props.call.contact.name ||
    props.call.contact.phoneNumber ||
    ''
  ).replace(/^\+/, '');
});

const agentActionLabel = computed(() => {
  if (!props.call.agent) return '';
  if (kind.value === CALL_KIND.OUTGOING) return t('CALLS_PAGE.ROW.DIALED_BY');
  if (kind.value === CALL_KIND.INCOMING) return t('CALLS_PAGE.ROW.PICKED_BY');
  // Ongoing collapses direction, so resolve dialed-vs-picked from the raw value.
  if (kind.value === CALL_KIND.ONGOING) {
    return props.call.direction === VOICE_CALL_DIRECTION.OUTBOUND
      ? t('CALLS_PAGE.ROW.DIALED_BY')
      : t('CALLS_PAGE.ROW.PICKED_BY');
  }
  return '';
});

const resultLabel = computed(() => {
  if (kind.value === CALL_KIND.MISSED) return t('CALLS_PAGE.ROW.NO_AGENT');
  if (kind.value === CALL_KIND.NO_REPLY) {
    return t('CALLS_PAGE.ROW.NO_CONTACT_ANSWER');
  }
  if (kind.value === CALL_KIND.FAILED) return t('CALLS_PAGE.ROW.FAILED');
  if (kind.value === CALL_KIND.ONGOING) {
    return props.call.status === VOICE_CALL_STATUS.RINGING
      ? t('CALLS_PAGE.ROW.RINGING')
      : t('CALLS_PAGE.ROW.IN_PROGRESS');
  }
  return t('CALLS_PAGE.ROW.ANSWERED');
});

const providerIcon = computed(() =>
  props.call.provider === 'asterisk'
    ? 'i-ri-phone-line'
    : getInboxVoiceIcon(props.call.inbox?.channelType, props.call.inbox?.medium)
);

// Discreet origin badge: routed by the voice bot, or the dialplan hint the call came in with.
const routeBadge = computed(() => {
  if (props.call.routedBy === 'bot')
    return {
      icon: 'i-lucide-bot',
      label: t('CALLS_PAGE.ROW.ROUTED_BY_BOT'),
      tooltip: t('CALLS_PAGE.ROW.ROUTED_BY_BOT_TOOLTIP'),
    };
  if (props.call.hint)
    return {
      icon: 'i-lucide-route',
      label: props.call.hint,
      tooltip: t('CALLS_PAGE.ROW.HINT_TOOLTIP', { hint: props.call.hint }),
    };
  return null;
});

const createdAtLabel = computed(() =>
  relativeDayTimestamp(props.call.createdAt, t('CALLS_PAGE.ROW.YESTERDAY'))
);

const conversationRoute = computed(() => ({
  name: 'inbox_conversation',
  params: {
    accountId: route.params.accountId,
    conversation_id: props.call.conversation?.displayId,
  },
  query: { messageId: props.call.messageId },
}));
</script>

<template>
  <div class="flex flex-col gap-2 py-3.5 border-b border-n-weak lg:hidden">
    <div class="flex items-center gap-2 min-w-0">
      <Avatar
        :src="call.contact?.avatar"
        :name="contactName"
        :size="24"
        rounded-full
      />
      <span
        v-tooltip.top="{ content: contactName, delay: { show: 500, hide: 0 } }"
        class="text-heading-3 font-medium truncate text-n-slate-12 min-w-0"
      >
        {{ contactName }}
      </span>
      <CallStatusBadge :kind="kind" class="ms-auto shrink-0" />
      <span
        v-if="routeBadge"
        v-tooltip.top="{
          content: routeBadge.tooltip,
          delay: { show: 500, hide: 0 },
        }"
        class="inline-flex items-center h-5 gap-1 px-1.5 rounded text-label-small bg-n-alpha-2 text-n-slate-11 shrink-0 max-w-24"
      >
        <Icon :icon="routeBadge.icon" class="size-3 shrink-0" />
        <span class="truncate">{{ routeBadge.label }}</span>
      </span>
      <button
        v-if="canJoin && kind === 'ongoing' && call.provider === 'asterisk'"
        type="button"
        class="inline-flex items-center h-6 gap-1 px-2 text-label-small rounded-md bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4 shrink-0"
        @click="emit('join', call)"
      >
        <Icon icon="i-lucide-phone-incoming" class="size-3.5" />
        {{ t('CALLS_PAGE.ROW.JOIN') }}
      </button>
      <RouterLink
        v-if="call.conversation"
        :to="conversationRoute"
        class="inline-flex items-center h-6 gap-1 px-2 text-label-small outline outline-1 -outline-offset-1 rounded-md outline-n-weak text-n-slate-11 hover:bg-n-alpha-1 shrink-0"
      >
        <Icon icon="i-lucide-message-circle" class="size-3.5 text-n-slate-11" />
        {{ call.conversation.displayId }}
        <Icon icon="i-lucide-arrow-up-right" class="size-3.5 text-n-slate-11" />
      </RouterLink>
    </div>
    <div class="flex items-center gap-1.5 min-w-0">
      <template v-if="agentActionLabel">
        <span class="text-label-small text-n-slate-10 shrink-0">
          {{ agentActionLabel }}
        </span>
        <Avatar
          :src="call.agent.avatar"
          :name="call.agent.name"
          :size="20"
          rounded-full
        />
        <span class="text-body-main truncate text-n-slate-12 min-w-0">
          {{ call.agent.name }}
        </span>
      </template>
      <span v-else class="text-body-main truncate text-n-slate-10 min-w-0">
        {{ resultLabel }}
      </span>
      <span class="w-px h-3 bg-n-strong shrink-0" />
      <Icon :icon="providerIcon" class="size-4 text-n-slate-11 shrink-0" />
      <span class="text-body-main truncate text-n-slate-11 min-w-0">
        {{ call.inbox?.name || t('CALLS_PAGE.ROW.INTERNAL') }}
      </span>
      <span
        v-if="!call.recordingUrl"
        class="ms-auto shrink-0 text-label-small text-n-slate-11 tabular-nums"
      >
        {{ createdAtLabel }}
      </span>
    </div>
    <div
      v-if="call.recordingUrl"
      class="flex items-center gap-2 min-w-0 justify-between"
    >
      <AudioPlayer
        :src="call.recordingUrl"
        :fallback-duration="call.durationSeconds || 0"
        class="flex-1 sm:flex-[0.7] min-w-0"
      />
      <span class="shrink-0 text-label-small text-n-slate-11 tabular-nums">
        {{ createdAtLabel }}
      </span>
    </div>
  </div>

  <div
    class="hidden items-center gap-x-1.5 gap-y-2.5 border-b border-n-weak lg:flex lg:items-center lg:gap-1.5"
  >
    <div class="flex items-center gap-2.5 min-w-0 w-52 shrink-0 py-3.5">
      <Avatar
        :src="call.contact?.avatar"
        :name="contactName"
        :size="24"
        rounded-full
      />
      <span
        v-tooltip.top="{ content: contactName, delay: { show: 500, hide: 0 } }"
        class="text-heading-3 font-medium truncate text-n-slate-12"
      >
        {{ contactName }}
      </span>
    </div>
    <div
      class="flex flex-nowrap items-center gap-x-2 gap-y-2 min-w-0 grow shrink"
    >
      <div class="flex items-center gap-x-2 min-w-0 lg:contents py-3.5">
        <CallStatusBadge :kind="kind" class="shrink-0" />
        <span
          v-if="routeBadge"
          v-tooltip.top="{
            content: routeBadge.tooltip,
            delay: { show: 500, hide: 0 },
          }"
          class="inline-flex items-center h-5 gap-1 px-1.5 rounded text-label-small bg-n-alpha-2 text-n-slate-11 shrink-0 max-w-24"
        >
          <Icon :icon="routeBadge.icon" class="size-3 shrink-0" />
          <span class="truncate">{{ routeBadge.label }}</span>
        </span>
        <div
          v-if="agentActionLabel"
          class="gap-x-1.5 min-w-0 flex items-center"
        >
          <span
            class="text-label-small text-n-slate-10 truncate shrink min-w-8 xl:min-w-14"
          >
            {{ agentActionLabel }}
          </span>
          <span class="flex items-center gap-1.5 min-w-16 shrink-[20]">
            <Avatar
              :src="call.agent.avatar"
              :name="call.agent.name"
              :size="20"
              rounded-full
            />
            <span
              v-tooltip.top="{
                content: call.agent.name,
                delay: { show: 500, hide: 0 },
              }"
              class="text-body-main truncate text-n-slate-12 min-w-0"
            >
              {{ call.agent.name }}
            </span>
          </span>
        </div>
        <span
          v-else-if="resultLabel"
          class="text-body-main truncate text-n-slate-10 min-w-0 shrink-[20]"
        >
          {{ resultLabel }}
        </span>
      </div>
      <AudioPlayer
        v-if="call.recordingUrl"
        :src="call.recordingUrl"
        :fallback-duration="call.durationSeconds || 0"
        class="w-auto min-w-44 shrink mx-auto"
      />
      <span
        v-else-if="call.recordingState === 'stored'"
        class="text-label-small text-n-slate-11 mx-auto shrink-0"
      >
        {{ t('CALLS_PAGE.ROW.RECORDING_PROCESSING') }}
      </span>
    </div>
    <div
      v-tooltip.top="{
        content: call.inbox?.name,
        delay: { show: 500, hide: 0 },
      }"
      class="flex items-center gap-1 justify-end w-40 min-w-4 shrink-[100] py-3.5"
    >
      <Icon :icon="providerIcon" class="size-4 text-n-slate-11 shrink-0" />
      <span class="text-body-main truncate text-n-slate-11 min-w-0">
        {{ call.inbox?.name || t('CALLS_PAGE.ROW.INTERNAL') }}
      </span>
    </div>
    <RouterLink
      v-if="call.conversation"
      :to="conversationRoute"
      class="inline-flex items-center h-6 gap-1 px-2 text-label-small py-3.5 outline outline-1 -outline-offset-1 rounded-md outline-n-weak text-n-slate-11 hover:bg-n-alpha-1 shrink-0 justify-self-start"
    >
      <Icon icon="i-lucide-message-circle" class="size-3.5 text-n-slate-11" />
      {{ call.conversation.displayId }}
      <Icon icon="i-lucide-arrow-up-right" class="size-3.5 text-n-slate-11" />
    </RouterLink>
    <span
      v-tooltip.top="{
        content: createdAtLabel,
        delay: { show: 500, hide: 0 },
      }"
      class="text-label-small text-end text-n-slate-11 truncate py-3.5 tabular-nums justify-self-end min-w-16 max-w-20 shrink-0"
    >
      {{ createdAtLabel }}
    </span>
  </div>
</template>
