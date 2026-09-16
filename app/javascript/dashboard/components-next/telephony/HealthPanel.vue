<script setup>
// Panel de salud de la telefonía (bloque `health` de GET telephony/status + `recordings` locales):
// versión y tiempo en pie del controlador, sesión ARI, cola hacia Chatwoot, llamadas vivas por estado,
// grabaciones pendientes/fallidas y lo que el barrido tuvo que corregir. Todo sin SSH.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  health: { type: Object, default: null },
  recordings: { type: Object, default: null },
  retrying: { type: Boolean, default: false },
});
const emit = defineEmits(['retryRecordings']);
const { t } = useI18n();
const k = (key, params) =>
  t(`INBOX_MGMT.SETTINGS_POPUP.TELEPHONY.HEALTH.${key}`, params);

const OUTBOX_WARN_S = 60;
const OUTBOX_BAD_S = 300;

const tone = level =>
  ({
    ok: 'bg-n-teal-3 text-n-teal-11',
    warn: 'bg-n-amber-3 text-n-amber-11',
    bad: 'bg-n-ruby-3 text-n-ruby-11',
    muted: 'bg-n-slate-3 text-n-slate-11',
  })[level];

const duration = seconds => {
  const s = Number(seconds) || 0;
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400)
    return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.floor(s / 86400)}d ${Math.floor((s % 86400) / 3600)}h`;
};
const since = iso => {
  if (!iso) return '—';
  return duration(Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000));
};

const h = computed(() => props.health || {});
const ari = computed(() => h.value.ari || {});
const outbox = computed(() => h.value.outbox || {});
const counters = computed(() => h.value.counters || {});
const callsByState = computed(() =>
  Object.entries(h.value.calls_by_state || {}).map(([state, v]) => ({
    state,
    count: v.count,
    oldest: v.oldest_seconds,
  }))
);
const rec = computed(() => ({
  pending: props.recordings?.pending || 0,
  failed: props.recordings?.failed || 0,
  missing: props.recordings?.missing || 0,
}));

const ariLevel = computed(() => {
  if (!ari.value.connected) return 'bad';
  return ari.value.reconnects > 0 ? 'warn' : 'ok';
});
const outboxLevel = computed(() => {
  const oldest = outbox.value.oldest_seconds || 0;
  if (oldest >= OUTBOX_BAD_S) return 'bad';
  if (oldest >= OUTBOX_WARN_S || outbox.value.failing > 0) return 'warn';
  return 'ok';
});
const recordingsLevel = computed(() => {
  if (rec.value.failed > 0) return 'warn';
  return rec.value.pending > 0 ? 'muted' : 'ok';
});
const sweepItems = computed(() =>
  ['pstn_gone', 'orphan_cleanup', 'bridge_failures', 'recordings_missing'].map(
    key => ({ key, value: counters.value[key] || 0 })
  )
);
const sweepLevel = computed(() =>
  sweepItems.value.some(i => i.value > 0) ? 'warn' : 'ok'
);
const provisionLevel = computed(() =>
  (h.value.provision_errors || 0) > 0 ? 'bad' : 'ok'
);
const canRetry = computed(() => rec.value.failed + rec.value.pending > 0);
</script>

<template>
  <div v-if="health" class="grid gap-2 text-sm sm:grid-cols-2 lg:grid-cols-3">
    <!-- Controlador -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{
        k('CONTROLLER')
      }}</span>
      <span class="text-n-slate-12">
        {{ h.version || '—' }} · {{ k('UPTIME') }}
        {{ duration(h.uptime_seconds) }}
      </span>
      <span
        class="px-2 py-0.5 rounded-full self-start"
        :class="tone(provisionLevel)"
      >
        {{ k('PROVISION_ERRORS', { count: h.provision_errors || 0 }) }}
      </span>
    </div>

    <!-- ARI -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{ k('ARI') }}</span>
      <span class="px-2 py-0.5 rounded-full self-start" :class="tone(ariLevel)">
        {{
          ari.connected
            ? k('ARI_CONNECTED_FOR', { for: since(ari.connected_since) })
            : k('ARI_DISCONNECTED')
        }}
      </span>
      <span class="text-n-slate-11">
        {{ k('RECONNECTS', { count: ari.reconnects || 0 }) }}
        <template v-if="ari.last_disconnect">
          · {{ k('LAST_DISCONNECT') }} {{ ari.last_disconnect }}
        </template>
      </span>
    </div>

    <!-- Cola hacia Chatwoot -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{ k('OUTBOX') }}</span>
      <span
        class="px-2 py-0.5 rounded-full self-start"
        :class="tone(outboxLevel)"
      >
        {{ k('OUTBOX_PENDING', { count: outbox.pending || 0 }) }}
        <template v-if="outbox.pending > 0">
          · {{ k('OLDEST') }} {{ duration(outbox.oldest_seconds) }}
        </template>
      </span>
      <span v-if="outbox.failing > 0" class="text-n-amber-11">
        {{ k('OUTBOX_FAILING', { count: outbox.failing }) }}
      </span>
    </div>

    <!-- Llamadas vivas -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{
        k('LIVE_CALLS')
      }}</span>
      <div class="flex flex-wrap gap-1">
        <span
          v-if="!callsByState.length"
          class="px-2 py-0.5 rounded-full"
          :class="tone('ok')"
        >
          {{ k('NO_LIVE_CALLS') }}
        </span>
        <span
          v-for="c in callsByState"
          :key="c.state"
          class="px-2 py-0.5 rounded-full"
          :class="tone('muted')"
        >
          {{ c.state }}: {{ c.count }} · {{ duration(c.oldest) }}
        </span>
      </div>
      <span class="text-n-slate-11">
        {{ k('LEGS_LIVE', { count: h.legs_live || 0 }) }}
        <template v-if="h.busy_calls">
          · {{ k('BUSY', { count: h.busy_calls }) }}
        </template>
      </span>
    </div>

    <!-- Grabaciones -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{
        k('RECORDINGS')
      }}</span>
      <span
        class="px-2 py-0.5 rounded-full self-start"
        :class="tone(recordingsLevel)"
      >
        {{ k('RECORDINGS_PENDING', { count: rec.pending }) }}
        · {{ k('RECORDINGS_FAILED', { count: rec.failed }) }} ·
        {{ k('RECORDINGS_MISSING', { count: rec.missing }) }}
      </span>
      <NextButton
        v-if="canRetry"
        xs
        ghost
        slate
        icon="i-lucide-rotate-ccw"
        :label="k('RETRY_RECORDINGS')"
        :is-loading="retrying"
        class="self-start"
        @click="emit('retryRecordings')"
      />
    </div>

    <!-- Barrido -->
    <div class="rounded-lg border border-n-weak p-3 flex flex-col gap-1">
      <span class="text-n-slate-11 text-xs uppercase">{{ k('SWEEP') }}</span>
      <div class="flex flex-wrap gap-1">
        <span
          v-for="i in sweepItems"
          :key="i.key"
          class="px-2 py-0.5 rounded-full"
          :class="tone(i.value > 0 ? 'warn' : 'muted')"
        >
          {{ k(`SWEEP_${i.key.toUpperCase()}`) }}: {{ i.value }}
        </span>
      </div>
      <span class="text-n-slate-11"
        >{{ k('SWEEP_HELP') }} ({{
          sweepLevel === 'ok' ? k('SWEEP_CLEAN') : k('SWEEP_ATTENTION')
        }})</span
      >
    </div>
  </div>
</template>
