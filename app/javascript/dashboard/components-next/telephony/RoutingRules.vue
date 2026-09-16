<script setup>
// Editor de reglas de enrutamiento de entrantes (pestaña Telephony del inbox).
// Cada regla: condiciones (cualquiera/sí/no…) → destino (agente, equipo, extensión, ring group, IVR, buzón, colgar).
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import TelephonyAPI from 'dashboard/api/telephony';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  extensions: { type: Array, default: () => [] },
  ringGroups: { type: Array, default: () => [] },
  endpoints: { type: Array, default: () => [] },
});
const { t } = useI18n();
const store = useStore();

const TRISTATE = ['any', 'yes', 'no'];
const HOURS = ['any', 'in', 'out'];
const DESTINATIONS = [
  'assignee',
  'agent',
  'team',
  'extension',
  'ringgroup',
  'ivr',
  'voicemail',
  'hangup',
];
const RINGING = ['assignee', 'agent', 'team', 'extension', 'ringgroup'];
const DEFAULT_TIMEOUT = 20;

const rules = ref([]);
const ivrs = ref([]);
const busy = ref(null);
const teams = computed(() => store.getters['teams/getTeams']);
const agents = computed(() => store.getters['agents/getAgents']);
const agentsWithExtension = computed(() => {
  const byUser = Object.fromEntries(
    props.endpoints.map(e => [e.user_id, e.extension])
  );
  return agents.value
    .filter(a => byUser[a.id])
    .map(a => ({ ...a, extension: byUser[a.id] }));
});

const blankRule = () => ({
  name: '',
  enabled: true,
  conditions: {
    contact_known: 'any',
    open_conversation: 'any',
    assignee_online: 'any',
    business_hours: 'any',
    dids: '',
    caller_prefix: '',
    hint: '',
  },
  destination: { type: 'assignee', timeout: DEFAULT_TIMEOUT },
});

// Ring group members ring in Chatwoot unless the rule says otherwise (expand: false = FreePBX rings them).
const normalizeDestination = destination => {
  const dest = { timeout: DEFAULT_TIMEOUT, ...(destination || {}) };
  if (dest.type === 'ringgroup' && dest.expand == null) dest.expand = true;
  return dest;
};

const normalize = rule => ({
  ...rule,
  conditions: { ...blankRule().conditions, ...(rule.conditions || {}) },
  destination: normalizeDestination(rule.destination),
});

const load = async () => {
  try {
    rules.value = (await TelephonyAPI.routingRules()).map(normalize);
  } catch (e) {
    rules.value = [];
  }
  try {
    ivrs.value = await TelephonyAPI.ivrs();
  } catch (e) {
    ivrs.value = [];
  }
};

const payload = rule => ({
  name: rule.name,
  enabled: rule.enabled,
  conditions: rule.conditions,
  destination: rule.destination,
});

const addRule = async () => {
  busy.value = 'new';
  try {
    rules.value.push(
      normalize(await TelephonyAPI.createRoutingRule(payload(blankRule())))
    );
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ERROR'));
  } finally {
    busy.value = null;
  }
};

const save = async rule => {
  busy.value = rule.id;
  try {
    const saved = await TelephonyAPI.updateRoutingRule(rule.id, payload(rule));
    Object.assign(rule, normalize(saved));
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.SAVED'));
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ERROR'));
  } finally {
    busy.value = null;
  }
};

const remove = async rule => {
  busy.value = rule.id;
  try {
    await TelephonyAPI.deleteRoutingRule(rule.id);
    rules.value = rules.value.filter(r => r.id !== rule.id);
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ERROR'));
  } finally {
    busy.value = null;
  }
};

const move = async (index, delta) => {
  const target = index + delta;
  if (target < 0 || target >= rules.value.length) return;
  const reordered = [...rules.value];
  [reordered[index], reordered[target]] = [reordered[target], reordered[index]];
  rules.value = reordered;
  try {
    await TelephonyAPI.reorderRoutingRules(reordered.map(r => r.id));
  } catch (e) {
    useAlert(t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ERROR'));
  }
};

const onTypeChange = rule => {
  const { type, timeout } = rule.destination;
  rule.destination = normalizeDestination({
    type,
    timeout: timeout || DEFAULT_TIMEOUT,
  });
};

onMounted(async () => {
  await store.dispatch('teams/get');
  await load();
});
</script>

<template>
  <div class="flex flex-col gap-3">
    <p class="help-text">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.HELP') }}
    </p>
    <p v-if="!rules.length" class="text-sm text-n-amber-11">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.EMPTY') }}
    </p>
    <div
      v-for="(rule, index) in rules"
      :key="rule.id"
      class="rounded-lg border border-n-weak p-3 flex flex-col gap-3"
    >
      <div class="flex items-center gap-2">
        <span class="text-xs text-n-slate-11 w-5">{{ index + 1 }}.</span>
        <input
          v-model="rule.name"
          type="text"
          class="!mb-0 flex-1"
          :placeholder="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.NAME')"
        />
        <label class="flex items-center gap-1 !mb-0 text-xs">
          <input v-model="rule.enabled" type="checkbox" class="!mb-0 w-auto" />
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ENABLED') }}
        </label>
        <NextButton
          v-tooltip="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.MOVE_UP')"
          xs
          ghost
          slate
          icon="i-lucide-arrow-up"
          :disabled="index === 0"
          @click="move(index, -1)"
        />
        <NextButton
          v-tooltip="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.MOVE_DOWN')"
          xs
          ghost
          slate
          icon="i-lucide-arrow-down"
          :disabled="index === rules.length - 1"
          @click="move(index, 1)"
        />
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
        <span class="col-span-full text-n-slate-11">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.WHEN') }}
        </span>
        <label class="!mb-0">
          {{
            t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.CONTACT_KNOWN')
          }}
          <select v-model="rule.conditions.contact_known" class="!mb-0">
            <option v-for="v in TRISTATE" :key="v" :value="v">
              {{
                t(
                  `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.${v.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>
        <label class="!mb-0">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.OPEN_CONVERSATION'
            )
          }}
          <select v-model="rule.conditions.open_conversation" class="!mb-0">
            <option v-for="v in TRISTATE" :key="v" :value="v">
              {{
                t(
                  `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.${v.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>
        <label class="!mb-0">
          {{
            t(
              'INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.ASSIGNEE_ONLINE'
            )
          }}
          <select v-model="rule.conditions.assignee_online" class="!mb-0">
            <option v-for="v in TRISTATE" :key="v" :value="v">
              {{
                t(
                  `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.${v.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>
        <label class="!mb-0">
          {{
            t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.BUSINESS_HOURS')
          }}
          <select v-model="rule.conditions.business_hours" class="!mb-0">
            <option v-for="v in HOURS" :key="v" :value="v">
              {{
                t(
                  `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.${v.toUpperCase()}`
                )
              }}
            </option>
          </select>
        </label>
        <label class="!mb-0">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.DIDS') }}
          <input v-model="rule.conditions.dids" type="text" class="!mb-0" />
        </label>
        <label class="!mb-0">
          {{
            t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.CALLER_PREFIX')
          }}
          <input
            v-model="rule.conditions.caller_prefix"
            type="text"
            class="!mb-0"
          />
        </label>
        <label class="!mb-0">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.HINT') }}
          <input v-model="rule.conditions.hint" type="text" class="!mb-0" />
        </label>
        <p class="col-span-full help-text !mb-0">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.COND.HINT_HELP') }}
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
        <span class="col-span-full text-n-slate-11">
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.THEN') }}
        </span>
        <select
          v-model="rule.destination.type"
          class="!mb-0 col-span-2"
          @change="onTypeChange(rule)"
        >
          <option v-for="d in DESTINATIONS" :key="d" :value="d">
            {{
              t(
                `INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.DEST.${d.toUpperCase()}`
              )
            }}
          </option>
        </select>
        <select
          v-if="rule.destination.type === 'agent'"
          v-model="rule.destination.user_id"
          class="!mb-0"
        >
          <option v-for="a in agentsWithExtension" :key="a.id" :value="a.id">
            {{ a.name }} ({{ a.extension }})
          </option>
        </select>
        <select
          v-if="rule.destination.type === 'team'"
          v-model="rule.destination.team_id"
          class="!mb-0"
        >
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
        <select
          v-if="['extension', 'voicemail'].includes(rule.destination.type)"
          v-model="rule.destination.extension"
          class="!mb-0"
        >
          <option v-for="ext in extensions" :key="ext.ext" :value="ext.ext">
            {{ ext.ext }} — {{ ext.name }}
          </option>
        </select>
        <select
          v-if="rule.destination.type === 'ringgroup'"
          v-model="rule.destination.number"
          class="!mb-0"
        >
          <option v-for="g in ringGroups" :key="g.number" :value="g.number">
            {{ g.number }} — {{ g.description }}
          </option>
        </select>
        <select
          v-if="rule.destination.type === 'ivr'"
          v-model="rule.destination.ivr_id"
          class="!mb-0"
        >
          <option v-for="ivr in ivrs" :key="ivr.id" :value="ivr.id">
            {{ ivr.name }}
          </option>
        </select>
        <label
          v-if="RINGING.includes(rule.destination.type)"
          class="!mb-0 flex items-center gap-1"
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.TIMEOUT') }}
          <input
            v-model.number="rule.destination.timeout"
            type="number"
            min="5"
            max="120"
            class="!mb-0 w-20"
          />
        </label>
        <label
          v-if="rule.destination.type === 'extension'"
          v-tooltip.top="
            t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.MAX_SECONDS_HELP')
          "
          class="!mb-0 flex items-center gap-1"
        >
          {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.MAX_SECONDS') }}
          <input
            v-model.number="rule.destination.max_seconds"
            type="number"
            min="5"
            max="600"
            placeholder="—"
            class="!mb-0 w-20"
          />
        </label>
        <label
          v-if="rule.destination.type === 'ringgroup'"
          class="!mb-0 col-span-full flex items-center gap-2"
        >
          <input
            v-model="rule.destination.expand"
            type="checkbox"
            class="!mb-0 w-auto"
          />
          {{
            t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.EXPAND_RINGGROUP')
          }}
        </label>
      </div>

      <div class="flex gap-2 justify-end">
        <NextButton
          sm
          ghost
          ruby
          :is-loading="busy === rule.id"
          :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.DELETE')"
          @click="remove(rule)"
        />
        <NextButton
          sm
          solid
          blue
          :is-loading="busy === rule.id"
          :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.SAVE')"
          @click="save(rule)"
        />
      </div>
    </div>
    <div>
      <NextButton
        sm
        faded
        blue
        icon="i-lucide-plus"
        :is-loading="busy === 'new'"
        :label="t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.ADD')"
        @click="addRule"
      />
    </div>
    <p class="help-text">
      {{ t('INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.ROUTING.FREEPBX_HINT') }}
    </p>
  </div>
</template>
