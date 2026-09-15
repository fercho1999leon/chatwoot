<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TrunkForm from 'dashboard/components-next/telephony/TrunkForm.vue';
import PbxForm from 'dashboard/components-next/telephony/PbxForm.vue';
import PbxTestResult from 'dashboard/components-next/telephony/PbxTestResult.vue';
import { useTelephonyPbx } from 'dashboard/composables/useTelephonyPbx';

const { t } = useI18n();
const store = useStore();

// Paso 1: conexión a la PBX de la cuenta (una vez); paso 2: troncal del carrier.
const {
  pbx,
  configured: pbxConfigured,
  loading: pbxLoading,
  saving: pbxSaving,
  testing: pbxTesting,
  testResult: pbxTestResult,
  load: loadPbx,
  save: savePbx,
  test: testPbx,
} = useTelephonyPbx();
const editingPbx = ref(false);
const channelName = ref('Telephony');
const trunk = ref({
  trunk_mode: 'custom',
  trunk_name: '',
  host: '',
  port: 5060,
  transport: 'udp',
  auth_mode: 'register',
  username: '',
  password: '',
  register: true,
  carrier_ips: [],
  caller_id: '',
  dids: '',
  codecs: ['ulaw', 'alaw'],
  dtmf: 'rfc4733',
  default_country: '',
  max_call_seconds: 3600,
  allowed_inbox_ids: [],
});
const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);
const isValid = computed(
  () =>
    channelName.value.trim() &&
    (trunk.value.trunk_mode === 'routes' ||
      (trunk.value.trunk_mode === 'gui'
        ? trunk.value.trunk_name
        : trunk.value.host))
);

const onSavePbx = async () => {
  if (await savePbx()) editingPbx.value = false;
};

onMounted(loadPbx);

const createChannel = async () => {
  if (!isValid.value) return;
  try {
    const inbox = await store.dispatch('inboxes/createChannel', {
      name: channelName.value.trim(),
      channel: { type: 'telephony', ...trunk.value },
    });
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: { page: 'new', inbox_id: inbox.id },
    });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.TELEPHONY.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <PageHeader
      :header-title="t('INBOX_MGMT.ADD.TELEPHONY.TITLE')"
      :header-content="t('INBOX_MGMT.ADD.TELEPHONY.DESC')"
    />
    <div
      v-if="!pbxLoading && (!pbxConfigured || editingPbx)"
      class="flex flex-col gap-4 mx-0 max-w-3xl"
    >
      <h3 class="text-base font-medium text-n-slate-12">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.STEP_TITLE') }}
      </h3>
      <p class="help-text">{{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.STEP_HELP') }}</p>
      <PbxForm v-model="pbx" />
      <PbxTestResult :result="pbxTestResult" />
      <div class="flex gap-2">
        <NextButton
          faded
          slate
          :is-loading="pbxTesting"
          :label="t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST.BUTTON')"
          @click="testPbx"
        />
        <NextButton
          solid
          blue
          :is-loading="pbxSaving"
          :label="t('INBOX_MGMT.ADD.TELEPHONY.PBX.SAVE')"
          @click="onSavePbx"
        />
      </div>
    </div>
    <form
      v-else-if="!pbxLoading"
      class="flex flex-col gap-4 mx-0 max-w-3xl"
      @submit.prevent="createChannel"
    >
      <div class="flex items-center gap-2 text-sm text-n-slate-11">
        <span class="i-lucide-check text-n-teal-11" />
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.CONFIGURED', { url: pbx.ari_url }) }}
        <NextButton
          sm
          link
          blue
          :label="t('INBOX_MGMT.ADD.TELEPHONY.PBX.EDIT')"
          @click="editingPbx = true"
        />
      </div>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.CHANNEL_NAME.LABEL') }}
        <input
          v-model="channelName"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.CHANNEL_NAME.PLACEHOLDER')"
        />
      </label>
      <TrunkForm v-model="trunk" />
      <div class="w-full mt-2">
        <NextButton
          :is-loading="uiFlags.isCreating"
          :disabled="!isValid"
          type="submit"
          solid
          blue
          :label="t('INBOX_MGMT.ADD.TELEPHONY.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
