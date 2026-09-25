<script setup>
// Formulario de troncal SIP (alta del inbox Telephony y pestaña de ajustes).
// v-model: objeto con los campos de Channel::Telephony (password '********' = conservar).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  modelValue: { type: Object, required: true },
  inboxes: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const TRANSPORTS = ['udp', 'tcp', 'tls'];
const AUTH_MODES = ['register', 'ip'];
const CODECS = ['ulaw', 'alaw', 'g722', 'opus', 'g729', 'gsm'];
const DTMF = ['rfc4733', 'inband', 'info', 'auto'];

const form = computed({
  get: () => props.modelValue,
  set: v => emit('update:modelValue', v),
});
const set = (key, value) =>
  emit('update:modelValue', { ...props.modelValue, [key]: value });
const toggleIn = (key, value) => {
  const list = props.modelValue[key] || [];
  set(
    key,
    list.includes(value) ? list.filter(v => v !== value) : [...list, value]
  );
};
const carrierIpsText = computed({
  get: () => (props.modelValue.carrier_ips || []).join(', '),
  set: v =>
    set(
      'carrier_ips',
      v
        .split(/[,\s]+/)
        .map(s => s.trim())
        .filter(Boolean)
    ),
});
const isGui = computed(() => form.value.trunk_mode === 'gui');
const isRoutes = computed(() => form.value.trunk_mode === 'routes');
const isCustom = computed(() => !isGui.value && !isRoutes.value);
</script>

<template>
  <div class="flex flex-col gap-4">
    <label>
      {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.LABEL') }}
      <select
        :value="form.trunk_mode"
        @change="set('trunk_mode', $event.target.value)"
      >
        <option value="custom">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.CUSTOM') }}
        </option>
        <option value="gui">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.GUI') }}
        </option>
        <option value="routes">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.ROUTES') }}
        </option>
      </select>
      <p class="help-text">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.HELP') }}
      </p>
    </label>

    <label v-if="isGui">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_NAME.LABEL') }}
      <input
        :value="form.trunk_name"
        type="text"
        :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_NAME.PLACEHOLDER')"
        @input="set('trunk_name', $event.target.value)"
      />
      <p class="help-text">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_NAME.HELP') }}
      </p>
    </label>

    <p v-if="isRoutes" class="help-text">
      {{ t('INBOX_MGMT.ADD.TELEPHONY.TRUNK_MODE.ROUTES_HELP') }}
    </p>

    <template v-if="isCustom">
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <label class="md:col-span-2">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.HOST.LABEL') }}
          <input
            :value="form.host"
            type="text"
            :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.HOST.PLACEHOLDER')"
            @input="set('host', $event.target.value)"
          />
        </label>
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PORT.LABEL') }}
          <input
            :value="form.port"
            type="number"
            min="1"
            max="65535"
            @input="set('port', Number($event.target.value))"
          />
        </label>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.TRANSPORT.LABEL') }}
          <select
            :value="form.transport"
            @change="set('transport', $event.target.value)"
          >
            <option v-for="tr in TRANSPORTS" :key="tr" :value="tr">
              {{ tr.toUpperCase() }}
            </option>
          </select>
        </label>
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.AUTH_MODE.LABEL') }}
          <select
            :value="form.auth_mode"
            @change="set('auth_mode', $event.target.value)"
          >
            <option v-for="a in AUTH_MODES" :key="a" :value="a">
              {{ t(`INBOX_MGMT.ADD.TELEPHONY.AUTH_MODE.${a.toUpperCase()}`) }}
            </option>
          </select>
        </label>
      </div>
      <div
        v-if="form.auth_mode === 'register'"
        class="grid grid-cols-1 md:grid-cols-2 gap-3"
      >
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.USERNAME.LABEL') }}
          <input
            :value="form.username"
            type="text"
            autocomplete="off"
            @input="set('username', $event.target.value)"
          />
        </label>
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.PASSWORD.LABEL') }}
          <input
            :value="form.password"
            type="password"
            autocomplete="new-password"
            @input="set('password', $event.target.value)"
          />
          <p class="help-text">
            {{ t('INBOX_MGMT.ADD.TELEPHONY.PASSWORD.HELP') }}
          </p>
        </label>
        <label class="md:col-span-2 flex items-center gap-2">
          <input
            type="checkbox"
            :checked="form.register"
            @change="set('register', $event.target.checked)"
          />
          {{ t('INBOX_MGMT.ADD.TELEPHONY.REGISTER.LABEL') }}
        </label>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <label>
          {{ t('INBOX_MGMT.ADD.TELEPHONY.DTMF.LABEL') }}
          <select :value="form.dtmf" @change="set('dtmf', $event.target.value)">
            <option v-for="d in DTMF" :key="d" :value="d">{{ d }}</option>
          </select>
        </label>
      </div>
      <div>
        <span class="text-sm font-medium">{{
          t('INBOX_MGMT.ADD.TELEPHONY.CODECS.LABEL')
        }}</span>
        <div class="flex flex-wrap gap-3 mt-1">
          <label
            v-for="c in CODECS"
            :key="c"
            class="flex items-center gap-1 !mb-0"
          >
            <input
              type="checkbox"
              :checked="(form.codecs || []).includes(c)"
              @change="toggleIn('codecs', c)"
            />
            {{ c }}
          </label>
        </div>
      </div>
    </template>

    <!-- Común a todos los modos: IPs del carrier (firewall de la PBX), entrantes (DIDs) y Caller ID saliente -->
    <label>
      {{ t('INBOX_MGMT.ADD.TELEPHONY.CARRIER_IPS.LABEL') }}
      <input
        v-model="carrierIpsText"
        type="text"
        :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.CARRIER_IPS.PLACEHOLDER')"
      />
      <p class="help-text">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.CARRIER_IPS.HELP') }}
      </p>
    </label>
    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.DIDS.LABEL') }}
        <input
          :value="form.dids"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.DIDS.PLACEHOLDER')"
          @input="set('dids', $event.target.value)"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.DIDS.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.CALLER_ID.LABEL') }}
        <input
          :value="form.caller_id"
          type="text"
          :placeholder="t('INBOX_MGMT.ADD.TELEPHONY.CALLER_ID.PLACEHOLDER')"
          @input="set('caller_id', $event.target.value)"
        />
      </label>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.DEFAULT_COUNTRY.LABEL') }}
        <input
          :value="form.default_country"
          type="text"
          maxlength="2"
          :placeholder="
            t('INBOX_MGMT.ADD.TELEPHONY.DEFAULT_COUNTRY.PLACEHOLDER')
          "
          @input="set('default_country', $event.target.value.toUpperCase())"
        />
        <p class="help-text">
          {{ t('INBOX_MGMT.ADD.TELEPHONY.DEFAULT_COUNTRY.HELP') }}
        </p>
      </label>
      <label>
        {{ t('INBOX_MGMT.ADD.TELEPHONY.MAX_CALL_SECONDS.LABEL') }}
        <input
          :value="form.max_call_seconds"
          type="number"
          min="60"
          max="14400"
          @input="set('max_call_seconds', Number($event.target.value))"
        />
      </label>
    </div>

    <div v-if="inboxes.length">
      <span class="text-sm font-medium">{{
        t('INBOX_MGMT.ADD.TELEPHONY.ALLOWED_INBOXES.LABEL')
      }}</span>
      <p class="help-text">
        {{ t('INBOX_MGMT.ADD.TELEPHONY.ALLOWED_INBOXES.HELP') }}
      </p>
      <div class="flex flex-wrap gap-3 mt-1">
        <label
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex items-center gap-1 !mb-0"
        >
          <input
            type="checkbox"
            :checked="(form.allowed_inbox_ids || []).includes(inbox.id)"
            @change="toggleIn('allowed_inbox_ids', inbox.id)"
          />
          {{ inbox.name }}
        </label>
      </div>
    </div>
  </div>
</template>
