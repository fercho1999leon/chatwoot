<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { messageTimestamp } from 'shared/helpers/timeHelper';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';

const BYTES_IN_A_KILOBYTE = 1024;
const BYTES_IN_A_MEGABYTE = 1024 * 1024;

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const records = computed(
  () => getters['datasetExports/getDatasetExports'].value
);
const uiFlags = computed(() => getters['datasetExports/getUIFlags'].value);

const tableHeaders = computed(() => [
  t('DATASET_EXPORTS.LIST.TABLE_HEADER.FORMAT'),
  t('DATASET_EXPORTS.LIST.TABLE_HEADER.CONVERSATIONS'),
  t('DATASET_EXPORTS.LIST.TABLE_HEADER.STATUS'),
  t('DATASET_EXPORTS.LIST.TABLE_HEADER.CREATED_BY'),
  t('DATASET_EXPORTS.LIST.TABLE_HEADER.TIME'),
  '',
  '',
]);

const formatLabel = exportRecord =>
  t(`DATASET_EXPORTS.FORMATS.${exportRecord.export_format.toUpperCase()}`);

const statusLabel = exportRecord =>
  t(`DATASET_EXPORTS.STATUS.${exportRecord.status.toUpperCase()}`);

const fileSize = exportRecord => {
  const bytes = exportRecord.file_size;
  if (!bytes) return '';
  if (bytes < BYTES_IN_A_MEGABYTE) {
    return `${Math.max(1, Math.round(bytes / BYTES_IN_A_KILOBYTE))} KB`;
  }
  return `${(bytes / BYTES_IN_A_MEGABYTE).toFixed(1)} MB`;
};

const deleteDialogRef = ref(null);
const exportToDelete = ref(null);

const openDeleteDialog = exportRecord => {
  exportToDelete.value = exportRecord;
  deleteDialogRef.value?.open();
};

const deleteExport = async () => {
  try {
    await store.dispatch('datasetExports/delete', exportToDelete.value.id);
    useAlert(t('DATASET_EXPORTS.DELETE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(error?.message || t('DATASET_EXPORTS.DELETE.ERROR_MESSAGE'));
  } finally {
    deleteDialogRef.value?.close();
    exportToDelete.value = null;
  }
};

const fetchDatasetExports = async () => {
  try {
    await store.dispatch('datasetExports/fetch');
  } catch (error) {
    useAlert(error?.message || t('DATASET_EXPORTS.API.ERROR_MESSAGE'));
  }
};

onMounted(fetchDatasetExports);
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.fetchingList"
    :loading-message="$t('DATASET_EXPORTS.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="$t('DATASET_EXPORTS.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('DATASET_EXPORTS.HEADER')"
        :description="$t('DATASET_EXPORTS.DESCRIPTION')"
      >
        <template #actions>
          <Button
            :label="$t('DATASET_EXPORTS.REFRESH')"
            icon="i-lucide-refresh-cw"
            slate
            ghost
            sm
            @click="fetchDatasetExports"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable :headers="tableHeaders" :items="records">
        <template #row="{ items }">
          <BaseTableRow
            v-for="exportRecord in items"
            :key="exportRecord.id"
            :item="exportRecord"
          >
            <template #default>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-12 whitespace-nowrap">
                  {{ formatLabel(exportRecord) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ exportRecord.conversations_count ?? '—' }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ statusLabel(exportRecord) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{ exportRecord.user?.name ?? '—' }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-body-main text-n-slate-11 whitespace-nowrap">
                  {{
                    messageTimestamp(exportRecord.created_at, 'LLL d, h:mm a')
                  }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <a
                  v-if="exportRecord.file_url"
                  :href="exportRecord.file_url"
                  class="inline-flex items-center gap-1 text-body-main text-n-brand whitespace-nowrap"
                  download
                >
                  <span class="i-lucide-download size-4" />
                  {{ $t('DATASET_EXPORTS.DOWNLOAD') }}
                  <span v-if="fileSize(exportRecord)" class="text-n-slate-11">
                    {{ `(${fileSize(exportRecord)})` }}
                  </span>
                </a>
              </BaseTableCell>
              <BaseTableCell>
                <Button
                  v-tooltip.top="$t('DATASET_EXPORTS.DELETE.BUTTON')"
                  :aria-label="$t('DATASET_EXPORTS.DELETE.BUTTON')"
                  icon="i-lucide-trash-2"
                  ruby
                  xs
                  faded
                  @click="openDeleteDialog(exportRecord)"
                />
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>
  </SettingsLayout>
  <Dialog
    ref="deleteDialogRef"
    type="alert"
    :title="$t('DATASET_EXPORTS.DELETE.TITLE')"
    :description="$t('DATASET_EXPORTS.DELETE.DESCRIPTION')"
    :confirm-button-label="$t('DATASET_EXPORTS.DELETE.CONFIRM')"
    @confirm="deleteExport"
    @close="exportToDelete = null"
  />
</template>
