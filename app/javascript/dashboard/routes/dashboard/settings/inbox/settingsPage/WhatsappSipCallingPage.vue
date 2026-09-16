<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';
import TelephonyAPI from 'dashboard/api/telephony';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();

const config = ref({});
const remote = ref({});
const provision = ref({});
let provisionTimer = null;
const hostname = ref('');
const loading = ref(true);
const working = ref(false);

const enabled = computed(() => config.value.enabled === true);
const remoteSip = computed(() => remote.value?.sip?.status || '—');
const remoteCalling = computed(() => remote.value?.status || '—');
const phoneNumber = computed(
  () => props.inbox.provider_config?.phone_number || props.inbox.phone_number
);

const errorMessage = e =>
  e?.response?.data?.error ||
  e?.message ||
  t('INBOX_MGMT.WHATSAPP_SIP_CALLING.ERROR');

const load = async () => {
  loading.value = true;
  try {
    const [{ data }, pbx] = await Promise.all([
      InboxesAPI.whatsappSipCalling(props.inbox.id),
      TelephonyAPI.pbx().catch(() => ({})),
    ]);
    config.value = data.config || {};
    remote.value = data.remote || {};
    provision.value = data.provision || {};
    // The PBX reload runs in the background on the controller: poll until it settles.
    clearTimeout(provisionTimer);
    if (provision.value.provisioning) provisionTimer = setTimeout(load, 5000);
    // The SIP hostname is the PBX's public SIP/TLS name: the domain the agents' softphone uses.
    hostname.value = config.value.hostname || pbx.sip_domain || '';
  } catch (e) {
    useAlert(errorMessage(e));
  } finally {
    loading.value = false;
  }
};

const run = async action => {
  working.value = true;
  try {
    const { data } = await action();
    config.value = data.config || {};
    useAlert(t('INBOX_MGMT.WHATSAPP_SIP_CALLING.SAVED'));
    await load();
  } catch (e) {
    useAlert(errorMessage(e));
  } finally {
    working.value = false;
  }
};

const onEnable = () =>
  run(() =>
    InboxesAPI.enableWhatsappSipCalling(props.inbox.id, {
      hostname: hostname.value.trim(),
    })
  );
const onResync = () =>
  run(() =>
    InboxesAPI.enableWhatsappSipCalling(props.inbox.id, { resync: true })
  );
const onDisable = () =>
  run(() => InboxesAPI.disableWhatsappSipCalling(props.inbox.id));

onMounted(load);
onBeforeUnmount(() => clearTimeout(provisionTimer));
</script>

<template>
  <div class="flex flex-col gap-6 py-4">
    <div>
      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.HELP') }}
      </p>
    </div>

    <div v-if="loading" class="flex items-center gap-2 text-n-slate-11">
      <Spinner />
      {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.LOADING') }}
    </div>

    <template v-else>
      <div
        class="flex flex-wrap gap-x-6 gap-y-2 p-4 rounded-xl bg-n-alpha-1 text-body-main"
      >
        <span>
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.NUMBER') }}:
          <strong class="text-n-slate-12">{{ phoneNumber }}</strong>
        </span>
        <span>
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.PBX') }}:
          <strong
            :class="enabled ? 'text-n-teal-11' : 'text-n-slate-12'"
            class="capitalize"
          >
            {{
              enabled
                ? t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.ENABLED')
                : t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.DISABLED')
            }}
          </strong>
        </span>
        <span>
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.META_CALLING') }}:
          <strong class="text-n-slate-12">{{ remoteCalling }}</strong>
        </span>
        <span>
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.META_SIP') }}:
          <strong class="text-n-slate-12">{{ remoteSip }}</strong>
        </span>
        <span v-if="config.synced_at" class="text-n-slate-11">
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.SYNCED_AT') }}:
          {{ new Date(config.synced_at).toLocaleString() }}
        </span>
        <span v-if="remote.error" class="text-n-ruby-11 w-full">
          {{ remote.error }}
        </span>
        <span v-if="provision.provisioning" class="text-n-amber-11 w-full">
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.PROVISIONING') }}
        </span>
        <span
          v-else-if="provision.provisioned_at && !provision.error"
          class="text-n-slate-11 w-full"
        >
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.PROVISIONED_AT') }}:
          {{ new Date(provision.provisioned_at).toLocaleString() }}
        </span>
        <span
          v-if="provision.error || config.provision_error"
          class="text-n-ruby-11 w-full"
        >
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.STATUS.PROVISION_ERROR') }}:
          {{ provision.error || config.provision_error }}
        </span>
      </div>

      <label class="max-w-xl">
        {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.HOSTNAME.LABEL') }}
        <input
          v-model="hostname"
          type="text"
          :disabled="enabled"
          :placeholder="
            t('INBOX_MGMT.WHATSAPP_SIP_CALLING.HOSTNAME.PLACEHOLDER')
          "
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.HOSTNAME.HELP') }}
        </p>
      </label>

      <ul class="text-body-main text-n-slate-11 list-disc ps-5 max-w-2xl">
        <li>{{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.REQUIREMENTS.TOKEN') }}</li>
        <li>{{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.REQUIREMENTS.TLS') }}</li>
        <li>{{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.REQUIREMENTS.ROUTING') }}</li>
        <li>
          {{ t('INBOX_MGMT.WHATSAPP_SIP_CALLING.REQUIREMENTS.PERMISSION') }}
        </li>
      </ul>

      <div class="flex items-center gap-2">
        <NextButton
          v-if="!enabled"
          solid
          blue
          :label="t('INBOX_MGMT.WHATSAPP_SIP_CALLING.ENABLE')"
          :is-loading="working"
          :disabled="!hostname.trim()"
          @click="onEnable"
        />
        <template v-else>
          <NextButton
            faded
            slate
            :label="t('INBOX_MGMT.WHATSAPP_SIP_CALLING.RESYNC')"
            :is-loading="working"
            @click="onResync"
          />
          <NextButton
            faded
            ruby
            :label="t('INBOX_MGMT.WHATSAPP_SIP_CALLING.DISABLE')"
            :is-loading="working"
            @click="onDisable"
          />
        </template>
      </div>
    </template>
  </div>
</template>
