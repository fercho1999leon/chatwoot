<script setup>
import { ref, computed, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const props = defineProps({
  // Advanced filter query ({ payload: [...] }) currently applied to the list, if any
  currentFilterQuery: { type: Object, default: null },
  isExporting: { type: Boolean, default: false },
});

const emit = defineEmits(['export']);

const { t } = useI18n();
const FORMATS = ['chat_jsonl', 'raw_json'];
const STATUSES = ['resolved', 'open', 'pending', 'snoozed'];
const DEFAULT_LIMIT = 2000;
const MAX_LIMIT = 50000;
const CSAT_RATINGS = [1, 2, 3, 4, 5];
const SYSTEM_PROMPT_MAX_LENGTH = 2000;

const dialogRef = ref(null);
const inboxes = useMapGetter('inboxes/getInboxes');

const form = reactive({
  exportFormat: FORMATS[0],
  useCurrentFilter: false,
  status: STATUSES[0],
  inboxIds: [],
  since: '',
  until: '',
  limit: DEFAULT_LIMIT,
  anonymize: true,
  includePrivateNotes: false,
  includeBotMessages: false,
  minAgentMessages: 2,
  minUserMessages: 1,
  minCsat: '',
  systemPrompt: '',
  evalRatio: 0.1,
});

const formatOptions = FORMATS.map(value => ({
  value,
  label: t(`CONVERSATION.EXPORT_DATASET.FORMATS.${value.toUpperCase()}`),
}));
const statusOptions = STATUSES.map(value => ({
  value,
  label: t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${value}.TEXT`),
}));
const csatOptions = [
  { value: '', label: t('CONVERSATION.EXPORT_DATASET.FIELDS.MIN_CSAT_ANY') },
  ...CSAT_RATINGS.map(value => ({ value, label: String(value) })),
];
const inboxOptions = computed(() =>
  inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const hasCurrentFilter = computed(
  () => props.currentFilterQuery?.payload?.length > 0
);
const isChatFormat = computed(() => form.exportFormat === 'chat_jsonl');
const useCurrentFilter = computed(
  () => hasCurrentFilter.value && form.useCurrentFilter
);
const isFormInvalid = computed(
  () => form.limit < 1 || form.limit > MAX_LIMIT || props.isExporting
);

const exportParams = () => ({
  export_format: form.exportFormat,
  payload: useCurrentFilter.value ? props.currentFilterQuery.payload : null,
  status: useCurrentFilter.value ? null : form.status,
  inbox_ids: useCurrentFilter.value ? [] : form.inboxIds,
  since: useCurrentFilter.value ? null : form.since || null,
  until: useCurrentFilter.value ? null : form.until || null,
  limit: Number(form.limit),
  options: {
    anonymize: form.anonymize,
    include_private_notes: form.includePrivateNotes,
    include_bot_messages: form.includeBotMessages,
    min_agent_messages: Number(form.minAgentMessages),
    min_user_messages: Number(form.minUserMessages),
    min_csat: form.minCsat === '' ? null : Number(form.minCsat),
    system_prompt: isChatFormat.value ? form.systemPrompt : null,
    eval_ratio: isChatFormat.value ? Number(form.evalRatio) : null,
  },
});

const handleDialogConfirm = () => {
  emit('export', exportParams());
  dialogRef.value?.close();
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('CONVERSATION.EXPORT_DATASET.TITLE')"
    :description="t('CONVERSATION.EXPORT_DATASET.DESCRIPTION')"
    :confirm-button-label="t('CONVERSATION.EXPORT_DATASET.CONFIRM')"
    :is-loading="isExporting"
    :disable-confirm-button="isFormInvalid"
    @confirm="handleDialogConfirm"
  >
    <div class="flex flex-col gap-4">
      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.FORMAT') }}
          </label>
          <Select
            v-model="form.exportFormat"
            class="!w-full [&>select]:w-full"
            :options="formatOptions"
          />
        </div>
        <Input
          v-model="form.limit"
          type="number"
          :max="String(MAX_LIMIT)"
          :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.LIMIT')"
        />
      </div>

      <label
        v-if="hasCurrentFilter"
        class="flex items-center gap-2 text-sm text-n-slate-12"
      >
        <Checkbox v-model="form.useCurrentFilter" />
        {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.USE_CURRENT_FILTER') }}
      </label>

      <template v-if="!useCurrentFilter">
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.STATUS') }}
            </label>
            <Select
              v-model="form.status"
              class="!w-full [&>select]:w-full"
              :options="statusOptions"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.INBOXES') }}
            </label>
            <TagMultiSelectComboBox
              v-model="form.inboxIds"
              :options="inboxOptions"
              :placeholder="
                t('CONVERSATION.EXPORT_DATASET.FIELDS.INBOXES_PLACEHOLDER')
              "
            />
          </div>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <Input
            v-model="form.since"
            type="date"
            :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.SINCE')"
          />
          <Input
            v-model="form.until"
            type="date"
            :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.UNTIL')"
          />
        </div>
      </template>

      <h4 class="text-sm font-medium text-n-slate-12">
        {{ t('CONVERSATION.EXPORT_DATASET.OPTIONS_TITLE') }}
      </h4>
      <div class="flex flex-col gap-2">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Checkbox v-model="form.anonymize" />
          {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.ANONYMIZE') }}
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Checkbox v-model="form.includePrivateNotes" />
          {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.INCLUDE_PRIVATE_NOTES') }}
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Checkbox v-model="form.includeBotMessages" />
          {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.INCLUDE_BOT_MESSAGES') }}
        </label>
      </div>
      <div class="grid grid-cols-3 gap-4">
        <Input
          v-model="form.minAgentMessages"
          type="number"
          :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.MIN_AGENT_MESSAGES')"
        />
        <Input
          v-model="form.minUserMessages"
          type="number"
          :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.MIN_USER_MESSAGES')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION.EXPORT_DATASET.FIELDS.MIN_CSAT') }}
          </label>
          <Select
            v-model="form.minCsat"
            class="!w-full [&>select]:w-full"
            :options="csatOptions"
          />
        </div>
      </div>
      <template v-if="isChatFormat">
        <Input
          v-model="form.evalRatio"
          type="number"
          max="0.5"
          step="0.05"
          :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.EVAL_RATIO')"
        />
        <TextArea
          v-model="form.systemPrompt"
          class="w-full"
          :label="t('CONVERSATION.EXPORT_DATASET.FIELDS.SYSTEM_PROMPT')"
          :placeholder="
            t('CONVERSATION.EXPORT_DATASET.FIELDS.SYSTEM_PROMPT_PLACEHOLDER')
          "
          :max-length="SYSTEM_PROMPT_MAX_LENGTH"
        />
      </template>
    </div>
  </Dialog>
</template>
