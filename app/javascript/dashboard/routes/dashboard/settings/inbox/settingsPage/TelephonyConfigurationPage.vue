<script setup>
// Pestaña "Telephony" del inbox de tipo Channel::Telephony: troncal, estado de la PBX,
// agentes ↔ extensiones de FreePBX e inboxes desde los que se puede llamar.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import TelephonyAPI from 'dashboard/api/telephony';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import TrunkForm from 'dashboard/components-next/telephony/TrunkForm.vue';
import PbxForm from 'dashboard/components-next/telephony/PbxForm.vue';
import RoutingRules from 'dashboard/components-next/telephony/RoutingRules.vue';
import PbxTestResult from 'dashboard/components-next/telephony/PbxTestResult.vue';
import HealthPanel from 'dashboard/components-next/telephony/HealthPanel.vue';
import { useTelephonyPbx } from 'dashboard/composables/useTelephonyPbx';

const props = defineProps({ inbox: { type: Object, required: true } });
const { t } = useI18n();
const store = useStore();

const {
  pbx,
  configured: pbxConfigured,
  saving: pbxSaving,
  testing: pbxTesting,
  testResult: pbxTestResult,
  purging: pbxPurging,
  load: loadPbx,
  save: savePbx,
  test: testPbx,
  purgeRecordings,
} = useTelephonyPbx();
const purgeDays = ref(90);
const onPurge = () => {
  const before = new Date(Date.now() - purgeDays.value * 86400000);
  if (
    // eslint-disable-next-line no-alert
    window.confirm(
      t('INBOX_MGMT.ADD.TELEPHONY.PBX.PURGE.CONFIRM', { days: purgeDays.value })
    )
  )
    purgeRecordings(before.toISOString());
};
// Bot de voz: token por cuenta (se muestra una sola vez) + URLs de la API que consume.
const botToken = ref(null);
const botBusy = ref(false);
const botCallsUrl = `${window.location.origin}/api/v1/telephony/bot/calls/:id`;
const botRouteUrl = `${botCallsUrl}/route`;
const botApiRows = [
  { key: 'CALLS_URL', url: botCallsUrl },
  { key: 'ROUTE_URL', url: botRouteUrl },
];
const hasBotToken = computed(() => Boolean(pbx.value?.has_bot_token));

const copyText = async text => {
  await copyTextToClipboard(text);
  useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.COPIED'));
};

const generateBotToken = async (rotate = false) => {
  if (
    rotate &&
    // eslint-disable-next-line no-alert
    !window.confirm(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.ROTATE_CONFIRM'))
  )
    return;
  botBusy.value = true;
  try {
    const { token } = await TelephonyAPI.botToken();
    botToken.value = token;
    pbx.value = { ...pbx.value, has_bot_token: true };
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.ERROR'));
  } finally {
    botBusy.value = false;
  }
};

const revokeBotToken = async () => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.REVOKE_CONFIRM'))
  )
    return;
  botBusy.value = true;
  try {
    await TelephonyAPI.revokeBotToken();
    botToken.value = null;
    pbx.value = { ...pbx.value, has_bot_token: false };
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.REVOKED'));
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.ERROR'));
  } finally {
    botBusy.value = false;
  }
};

const setWebhookUrl = value => {
  pbx.value = { ...pbx.value, bot_webhook_url: value };
};

const trunk = ref({});
const saving = ref(false);
const status = ref(null);
const statusLoading = ref(false);
const extensions = ref([]);
const endpoints = ref([]);
const ringGroups = ref([]);
const selection = ref({}); // user_id → extension elegida en el select
const busyUser = ref(null);

const inboxes = computed(() =>
  store.getters['inboxes/getInboxes'].filter(i => i.id !== props.inbox.id)
);
const agents = computed(() => store.getters['agents/getAgents']);
const endpointByUser = computed(() =>
  Object.fromEntries(endpoints.value.map(e => [e.user_id, e]))
);
const registeredByExt = computed(() => {
  const map = {};
  (status.value?.agents || []).forEach(a => {
    map[a.endpoint] = a.registered;
  });
  return map;
});

const loadTrunk = () => {
  const tconf = props.inbox.telephony || {};
  trunk.value = {
    trunk_mode: tconf.trunk_mode || 'custom',
    trunk_name: tconf.trunk_name || '',
    host: tconf.host || '',
    port: tconf.port || 5060,
    transport: tconf.transport || 'udp',
    auth_mode: tconf.auth_mode || 'register',
    username: tconf.username || '',
    password: tconf.password || '',
    register: tconf.register !== false,
    carrier_ips: tconf.carrier_ips || [],
    caller_id: tconf.caller_id || '',
    dids: tconf.dids || '',
    codecs: tconf.codecs || ['ulaw', 'alaw'],
    dtmf: tconf.dtmf || 'rfc4733',
    default_country: tconf.default_country || '',
    max_call_seconds: tconf.max_call_seconds || 3600,
    allowed_inbox_ids: tconf.allowed_inbox_ids || [],
  };
};

const retryingRecordings = ref(false);
const onRetryRecordings = async () => {
  retryingRecordings.value = true;
  try {
    await TelephonyAPI.retryRecordings();
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.HEALTH.RETRY_QUEUED'));
  } catch (e) {
    useAlert(e?.response?.data?.code || 'unavailable');
  } finally {
    retryingRecordings.value = false;
  }
};

let provisioningTimer = null;
const loadStatus = async () => {
  statusLoading.value = true;
  try {
    status.value = await TelephonyAPI.status();
    // The PBX reload runs in the background on the controller: poll until it settles.
    clearTimeout(provisioningTimer);
    if (status.value?.provisioning)
      provisioningTimer = setTimeout(loadStatus, 5000);
  } catch (e) {
    status.value = { error: e?.response?.data?.code || 'unavailable' };
  } finally {
    statusLoading.value = false;
  }
};

const loadDirectory = async () => {
  try {
    [extensions.value, endpoints.value, ringGroups.value] = await Promise.all([
      TelephonyAPI.extensions().catch(() => []),
      TelephonyAPI.endpoints().catch(() => []),
      TelephonyAPI.ringGroups().catch(() => []),
    ]);
  } catch (e) {
    // handled per call
  }
  endpoints.value.forEach(e => {
    selection.value[e.user_id] = e.extension;
  });
};

const saveTrunk = async () => {
  saving.value = true;
  try {
    await store.dispatch('inboxes/updateInbox', {
      id: props.inbox.id,
      formData: false,
      channel: { ...trunk.value },
    });
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.SAVED'));
    setTimeout(loadStatus, 2500);
  } catch (e) {
    useAlert(e?.message || t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const assign = async (userId, rotate = false) => {
  const extension = selection.value[userId];
  if (!extension) return;
  busyUser.value = userId;
  try {
    await TelephonyAPI.assignExtension(userId, extension, rotate);
    await loadDirectory();
    await loadStatus();
    useAlert(
      t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.EXTENSION_LINKED', { extension })
    );
  } catch (e) {
    const code = e?.response?.data?.code || 'unknown';
    useAlert(
      t(
        `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.EXTENSION_ERROR.${code.toUpperCase()}`,
        t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.EXTENSION_ERROR.UNKNOWN')
      )
    );
  } finally {
    busyUser.value = null;
  }
};

const unassign = async userId => {
  busyUser.value = userId;
  try {
    await TelephonyAPI.unassignExtension(userId);
    delete selection.value[userId];
    await loadDirectory();
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.EXTENSION_ERROR.UNKNOWN'));
  } finally {
    busyUser.value = null;
  }
};

const extensionLabel = ext =>
  `${ext.ext} — ${ext.name}${ext.assigned_to ? ` (${t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.TAKEN')})` : ''}`;

const onSavePbx = async () => {
  if (await savePbx()) {
    // La sesión ARI se abre en segundo plano: releer estado y directorio en unos segundos.
    setTimeout(() => Promise.all([loadStatus(), loadDirectory()]), 2500);
  }
};

onBeforeUnmount(() => clearTimeout(provisioningTimer));
onMounted(async () => {
  loadTrunk();
  await store.dispatch('agents/get');
  await Promise.all([loadPbx(), loadStatus(), loadDirectory()]);
});
watch(() => props.inbox.telephony, loadTrunk, { deep: true });
</script>

<template>
  <div class="flex flex-col gap-8">
    <!-- Estado -->
    <SettingsFieldSection
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.TITLE')"
    >
      <div class="flex flex-wrap items-center gap-2 text-sm">
        <span
          class="px-2 py-0.5 rounded-full"
          :class="
            status?.ari_connected
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.PBX') }}
          {{
            status?.ari_connected
              ? t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.CONNECTED')
              : status?.pbx_configured === false
                ? t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.NOT_CONFIGURED')
                : t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.DISCONNECTED')
          }}
        </span>
        <span
          v-if="status?.test_mode"
          class="px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.TEST_MODE') }}
        </span>
        <span
          v-if="status?.provisioning"
          class="px-2 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.PROVISIONING') }}
        </span>
        <span
          v-if="status?.trunk"
          class="px-2 py-0.5 rounded-full"
          :class="
            status.trunk.provision_error
              ? 'bg-n-ruby-3 text-n-ruby-11'
              : 'bg-n-slate-3 text-n-slate-11'
          "
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.TRUNK') }}:
          <template v-if="status.trunk.mode === 'routes'">
            {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.TRUNK_ROUTES') }}
          </template>
          <template v-else>
            {{ status.trunk.name }} · {{ status.trunk.endpoint_state || '—' }}
          </template>
          <template v-if="status.trunk.registration">
            · {{ status.trunk.registration }}</template
          >
        </span>
        <span
          v-for="(state, name) in status?.trunk?.registrations || {}"
          :key="name"
          class="px-2 py-0.5 rounded-full"
          :class="
            state === 'Registered'
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-ruby-3 text-n-ruby-11'
          "
          :title="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.REGISTRATIONS')"
        >
          {{ name }} · {{ state }}
        </span>
        <span v-if="status?.trunk?.provision_error" class="text-n-ruby-11">{{
          status.trunk.provision_error
        }}</span>
        <span v-if="status?.active_calls != null" class="text-n-slate-11">{{
          t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.STATUS.ACTIVE_CALLS', {
            count: status.active_calls,
          })
        }}</span>
        <NextButton
          sm
          ghost
          slate
          icon="i-lucide-refresh-cw"
          :is-loading="statusLoading"
          @click="loadStatus"
        />
      </div>
    </SettingsFieldSection>

    <!-- Salud del controlador -->
    <SettingsFieldSection
      v-if="status?.health"
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.HEALTH.TITLE')"
    >
      <p class="help-text mb-3">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.HEALTH.HELP') }}
      </p>
      <HealthPanel
        :health="status.health"
        :recordings="status.recordings"
        :retrying="retryingRecordings"
        @retry-recordings="onRetryRecordings"
      />
    </SettingsFieldSection>

    <!-- Conexión PBX -->
    <SettingsFieldSection
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.PBX.TITLE')"
    >
      <p class="help-text mb-3">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.PBX.HELP') }}
      </p>
      <PbxForm v-model="pbx" />
      <div class="mt-4 flex flex-col gap-3">
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
        <div class="flex items-center gap-2 text-sm">
          <span>{{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PURGE.LABEL') }}</span>
          <input
            v-model.number="purgeDays"
            type="number"
            min="1"
            max="3650"
            class="!mb-0 w-24"
          />
          <span>{{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PURGE.DAYS') }}</span>
          <NextButton
            sm
            faded
            ruby
            :is-loading="pbxPurging"
            :label="t('INBOX_MGMT.ADD.TELEPHONY.PBX.PURGE.BUTTON')"
            @click="onPurge"
          />
        </div>
      </div>
    </SettingsFieldSection>

    <!-- Bot de voz (IA) -->
    <SettingsFieldSection
      v-if="pbxConfigured"
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.TITLE')"
    >
      <p class="help-text mb-3">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.HELP') }}
      </p>
      <div class="flex flex-col gap-5">
        <div class="flex flex-col gap-2">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.API_TITLE') }}
          </h4>
          <div
            v-for="row in botApiRows"
            :key="row.key"
            class="flex flex-wrap items-center gap-2 text-sm"
          >
            <span class="text-n-slate-11 w-44 shrink-0">
              {{ t(`INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.${row.key}`) }}
            </span>
            <code
              class="flex-1 min-w-0 rounded bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-12 truncate"
            >
              {{ row.url }}
            </code>
            <NextButton
              sm
              ghost
              slate
              icon="i-lucide-copy"
              @click="copyText(row.url)"
            />
          </div>
          <p class="help-text">
            {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.AUTH_HELP') }}
          </p>
        </div>

        <div class="flex flex-col gap-2">
          <h4 class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.TOKEN_TITLE') }}
          </h4>
          <p
            class="text-sm"
            :class="hasBotToken ? 'text-n-teal-11' : 'text-n-slate-11'"
          >
            {{
              hasBotToken
                ? t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.TOKEN_ACTIVE')
                : t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.TOKEN_NONE')
            }}
          </p>
          <div
            v-if="botToken"
            class="rounded-lg border border-n-amber-5 bg-n-amber-2 p-3 flex flex-col gap-2"
          >
            <p class="text-sm text-n-amber-11">
              {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.TOKEN_ONCE') }}
            </p>
            <div class="flex flex-wrap items-center gap-2">
              <code
                class="flex-1 min-w-0 break-all rounded bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-12 select-all"
              >
                {{ botToken }}
              </code>
              <NextButton
                sm
                faded
                slate
                icon="i-lucide-copy"
                :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.COPY')"
                @click="copyText(botToken)"
              />
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <NextButton
              v-if="!hasBotToken"
              solid
              blue
              :is-loading="botBusy"
              :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.GENERATE')"
              @click="generateBotToken(false)"
            />
            <template v-else>
              <NextButton
                faded
                slate
                :is-loading="botBusy"
                :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.ROTATE')"
                @click="generateBotToken(true)"
              />
              <NextButton
                faded
                ruby
                :is-loading="botBusy"
                :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.REVOKE')"
                @click="revokeBotToken"
              />
            </template>
          </div>
        </div>

        <label class="!mb-0">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.WEBHOOK_LABEL') }}
          <input
            :value="pbx.bot_webhook_url"
            type="url"
            @input="setWebhookUrl($event.target.value)"
          />
          <p class="help-text">
            {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.BOT.WEBHOOK_HELP') }}
          </p>
        </label>
        <div>
          <NextButton
            solid
            blue
            :is-loading="pbxSaving"
            :label="t('INBOX_MGMT.ADD.TELEPHONY.PBX.SAVE')"
            @click="onSavePbx"
          />
        </div>
      </div>
    </SettingsFieldSection>

    <!-- Troncal -->
    <SettingsFieldSection
      v-if="pbxConfigured"
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.TRUNK.TITLE')"
    >
      <TrunkForm v-model="trunk" :inboxes="inboxes" />
      <div class="mt-4">
        <NextButton
          solid
          blue
          :is-loading="saving"
          :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.TRUNK.SAVE')"
          @click="saveTrunk"
        />
      </div>
    </SettingsFieldSection>

    <!-- Agentes ↔ extensiones -->
    <SettingsFieldSection
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.TITLE')"
    >
      <p class="help-text mb-3">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.HELP') }}
      </p>
      <table class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11">
            <th class="py-1">
              {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.AGENT') }}
            </th>
            <th class="py-1">
              {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.EXTENSION') }}
            </th>
            <th class="py-1">
              {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.REGISTERED') }}
            </th>
            <th class="py-1" />
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="agent in agents"
            :key="agent.id"
            class="border-t border-n-weak"
          >
            <td class="py-2">{{ agent.name }}</td>
            <td class="py-2">
              <select v-model="selection[agent.id]" class="!mb-0">
                <option value="">—</option>
                <option
                  v-for="ext in extensions"
                  :key="ext.ext"
                  :value="ext.ext"
                  :disabled="
                    ext.assigned_to && ext.assigned_to.user_id !== agent.id
                  "
                >
                  {{ extensionLabel(ext) }}
                </option>
              </select>
            </td>
            <td class="py-2">
              <template v-if="endpointByUser[agent.id]">
                <span
                  :class="
                    registeredByExt[endpointByUser[agent.id].extension]
                      ? 'text-n-teal-11'
                      : 'text-n-slate-11'
                  "
                >
                  {{
                    registeredByExt[endpointByUser[agent.id].extension]
                      ? t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.YES')
                      : t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.NO')
                  }}
                </span>
              </template>
              <span v-else class="text-n-slate-10">—</span>
            </td>
            <td class="py-2 flex gap-1 justify-end">
              <NextButton
                sm
                solid
                blue
                :is-loading="busyUser === agent.id"
                :disabled="!selection[agent.id]"
                :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.LINK')"
                @click="assign(agent.id)"
              />
              <NextButton
                v-if="endpointByUser[agent.id]"
                v-tooltip="
                  t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.ROTATE')
                "
                sm
                ghost
                slate
                icon="i-lucide-key-round"
                @click="assign(agent.id, true)"
              />
              <NextButton
                v-if="endpointByUser[agent.id]"
                sm
                ghost
                ruby
                icon="i-lucide-unlink"
                @click="unassign(agent.id)"
              />
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="!extensions.length" class="help-text mt-2">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.AGENTS.NO_EXTENSIONS') }}
      </p>
    </SettingsFieldSection>

    <!-- Enrutamiento de entrantes -->
    <SettingsFieldSection
      v-if="pbxConfigured"
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.TITLE')"
    >
      <RoutingRules
        :extensions="extensions"
        :ring-groups="ringGroups"
        :endpoints="endpoints"
      />
    </SettingsFieldSection>

    <!-- Grupos (informativo) -->
    <SettingsFieldSection
      v-if="ringGroups.length"
      :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.GROUPS.TITLE')"
    >
      <ul class="text-sm">
        <li v-for="g in ringGroups" :key="g.number" class="py-1">
          <span class="font-medium">{{ g.number }}</span> —
          {{ g.description }} · {{ g.strategy }} · {{ g.members.join(', ') }}
        </li>
      </ul>
      <p class="help-text mt-1">
        {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.GROUPS.HELP') }}
      </p>
    </SettingsFieldSection>
  </div>
</template>
