<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TrunkForm from 'dashboard/components-next/telephony/TrunkForm.vue';

const { t } = useI18n();
const store = useStore();

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
    (trunk.value.trunk_mode === 'gui'
      ? trunk.value.trunk_name
      : trunk.value.host)
);

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
    <form
      class="flex flex-col gap-4 mx-0 max-w-3xl"
      @submit.prevent="createChannel"
    >
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
