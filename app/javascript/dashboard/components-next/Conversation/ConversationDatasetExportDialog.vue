<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
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
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');

const preview = ref(null);
const previewError = ref('');
const isPreviewing = ref(false);
const PREVIEW_TURNS_SHOWN = 4;

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

const runPreview = async () => {
  isPreviewing.value = true;
  previewError.value = '';
  try {
    preview.value = await store.dispatch('previewDataset', exportParams());
  } catch (error) {
    preview.value = null;
    previewError.value =
      error.message || t('CONVERSATION.EXPORT_DATASET.PREVIEW.ERROR');
  } finally {
    isPreviewing.value = false;
  }
};

// A preview describes one set of settings; changing them makes it stale.
watch(
  () => JSON.stringify(exportParams()),
  () => {
    preview.value = null;
    previewError.value = '';
  }
);

const previewTurns = computed(() =>
  (preview.value?.sample?.messages ?? [])
    .filter(message => message.role !== 'system')
    .slice(0, PREVIEW_TURNS_SHOWN)
);

const droppedEntries = computed(() =>
  Object.entries(preview.value?.dropped ?? {}).filter(([, count]) => count > 0)
);

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
      <div class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <div class="flex items-center justify-between gap-2">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('CONVERSATION.EXPORT_DATASET.PREVIEW.TITLE') }}
          </h4>
          <Button
            :label="t('CONVERSATION.EXPORT_DATASET.PREVIEW.RUN')"
            :is-loading="isPreviewing"
            :disabled="isPreviewing"
            icon="i-lucide-eye"
            type="button"
            slate
            faded
            sm
            @click="runPreview"
          />
        </div>
        <p v-if="previewError" class="text-sm text-n-ruby-11">
          {{ previewError }}
        </p>
        <p v-else-if="!preview" class="text-sm text-n-slate-11">
          {{ t('CONVERSATION.EXPORT_DATASET.PREVIEW.HINT') }}
        </p>
        <template v-else>
          <p class="text-sm text-n-slate-12">
            {{
              t('CONVERSATION.EXPORT_DATASET.PREVIEW.SUMMARY', {
                matching: preview.matching_count,
                analyzed: preview.analyzed_count,
                kept: preview.kept_count,
              })
            }}
          </p>
          <p
            v-for="[reason, count] in droppedEntries"
            :key="reason"
            class="text-sm text-n-slate-11"
          >
            {{
              t(
                `CONVERSATION.EXPORT_DATASET.PREVIEW.DROPPED.${reason.toUpperCase()}`,
                { count }
              )
            }}
          </p>
          <p v-if="!preview.kept_count" class="text-sm text-n-ruby-11">
            {{ t('CONVERSATION.EXPORT_DATASET.PREVIEW.EMPTY') }}
          </p>
          <div
            v-if="previewTurns.length"
            class="flex flex-col gap-1 p-3 rounded-lg bg-n-alpha-black2 max-h-48 overflow-y-auto"
          >
            <p
              v-for="(turn, index) in previewTurns"
              :key="index"
              class="text-sm text-n-slate-12"
            >
              <span class="font-medium text-n-slate-11">
                {{ `${turn.role}:` }}
              </span>
              {{ turn.content }}
            </p>
          </div>
        </template>
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
