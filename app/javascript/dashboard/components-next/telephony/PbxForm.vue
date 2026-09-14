<script setup>
// Conexión a la PBX (Asterisk/FreePBX) de la cuenta: ARI, WebSocket SIP del navegador,
// TURN, provisioner, modo prueba y tiempos. Secretos: '********' = conservar el guardado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const form = computed(() => props.modelValue);
// Technical examples (URLs), not translatable copy.
const EXAMPLES = {
  ari_url: 'https://pbx.example.com',
  sip_ws_url: 'wss://pbx.example.com/ws',
  sip_domain: 'pbx.example.com',
  stun_url: 'stun:pbx.example.com:3478',
  turn_urls:
    'turn:pbx.example.com:3478?transport=udp, turns:pbx.example.com:5349?transport=tcp',
  provision_url: 'https://pbx.example.com/provision',
};
const set = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const setInt = (key, value) => set(key, parseInt(value, 10) || 0);
const testMode = computed({
  get: () => Boolean(form.value.test_dial),
  set: v => set('test_dial', v ? 'Local/*43@from-internal' : ''),
});
</script>

<template>
  <div class="flex flex-col gap-4">
    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_TITLE') }}
    </h4>
    <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
      <label class="md:col-span-3">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_URL.LABEL') }}
        <input
          :value="form.ari_url"
          type="url"
          :placeholder="EXAMPLES.ari_url"
          @input="set('ari_url', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_URL.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_USER') }}
        <input
          :value="form.ari_user"
          type="text"
          @input="set('ari_user', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_PASSWORD') }}
        <input
          :value="form.ari_password"
          type="password"
          autocomplete="new-password"
          @input="set('ari_password', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_APP.LABEL') }}
        <input
          :value="form.ari_app"
          type="text"
          @input="set('ari_app', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_APP.HELP') }}
        </p>
      </label>
    </div>

    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.SIP_TITLE') }}
    </h4>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.SIP_WS_URL.LABEL') }}
        <input
          :value="form.sip_ws_url"
          type="text"
          :placeholder="EXAMPLES.sip_ws_url"
          @input="set('sip_ws_url', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.SIP_WS_URL.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.SIP_DOMAIN.LABEL') }}
        <input
          :value="form.sip_domain"
          type="text"
          :placeholder="EXAMPLES.sip_domain"
          @input="set('sip_domain', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.SIP_DOMAIN.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.STUN_URL') }}
        <input
          :value="form.stun_url"
          type="text"
          :placeholder="EXAMPLES.stun_url"
          @input="set('stun_url', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TURN_URLS.LABEL') }}
        <input
          :value="form.turn_urls"
          type="text"
          :placeholder="EXAMPLES.turn_urls"
          @input="set('turn_urls', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TURN_URLS.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TURN_SECRET.LABEL') }}
        <input
          :value="form.turn_secret"
          type="password"
          autocomplete="new-password"
          @input="set('turn_secret', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TURN_SECRET.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TURN_TTL') }}
        <input
          :value="form.turn_ttl_seconds"
          type="number"
          min="300"
          max="86400"
          @input="setInt('turn_ttl_seconds', $event.target.value)"
        />
      </label>
    </div>

    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PROVISION_TITLE') }}
    </h4>
    <p class="help-text">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PROVISION_HELP') }}
    </p>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PROVISION_URL') }}
        <input
          :value="form.provision_url"
          type="text"
          :placeholder="EXAMPLES.provision_url"
          @input="set('provision_url', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PROVISION_TOKEN') }}
        <input
          :value="form.provision_token"
          type="password"
          autocomplete="new-password"
          @input="set('provision_token', $event.target.value)"
        />
      </label>
    </div>

    <h4 class="text-sm font-medium text-n-slate-12">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.CALLS_TITLE') }}
    </h4>
    <label class="flex items-center gap-2">
      <input v-model="testMode" type="checkbox" class="!mb-0 w-auto" />
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST_MODE.LABEL') }}
    </label>
    <label v-if="testMode">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST_MODE.DIAL') }}
      <input
        :value="form.test_dial"
        type="text"
        @input="set('test_dial', $event.target.value)"
      />
      <p class="help-text">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST_MODE.HELP') }}
      </p>
    </label>
    <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.AGENT_TIMEOUT') }}
        <input
          :value="form.agent_timeout"
          type="number"
          min="5"
          max="120"
          @input="setInt('agent_timeout', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PSTN_TIMEOUT') }}
        <input
          :value="form.pstn_timeout"
          type="number"
          min="10"
          max="180"
          @input="setInt('pstn_timeout', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.TRANSFER_TIMEOUT') }}
        <input
          :value="form.transfer_timeout"
          type="number"
          min="5"
          max="120"
          @input="setInt('transfer_timeout', $event.target.value)"
        />
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.MAX_CALL_SECONDS') }}
        <input
          :value="form.max_call_seconds"
          type="number"
          min="60"
          max="14400"
          @input="setInt('max_call_seconds', $event.target.value)"
        />
      </label>
    </div>
  </div>
</template>
