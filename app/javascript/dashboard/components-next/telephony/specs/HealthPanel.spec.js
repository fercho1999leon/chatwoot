import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import HealthPanel from '../HealthPanel.vue';
import en from 'dashboard/i18n/locale/en/inboxMgmt.json';

const health = (overrides = {}) => ({
  version: 'v0.1.9',
  uptime_seconds: 3700,
  outbox: { pending: 0, oldest_seconds: 0, failing: 0 },
  ari: {
    connected: true,
    connected_since: new Date(Date.now() - 120000).toISOString(),
    reconnects: 0,
    last_disconnect: null,
  },
  counters: {
    pstn_gone: 0,
    orphan_cleanup: 0,
    bridge_failures: 0,
    recordings_missing: 0,
  },
  calls_by_state: {},
  legs_live: 0,
  busy_calls: 0,
  provision_errors: 0,
  ...overrides,
});

const mountPanel = props =>
  mount(HealthPanel, {
    props,
    global: {
      plugins: [createI18n({ legacy: false, locale: 'en', messages: { en } })],
      stubs: {
        NextButton: {
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label'],
          emits: ['click'],
        },
      },
    },
  });

describe('HealthPanel', () => {
  it('renders nothing without health', () => {
    expect(mountPanel({ health: null }).html()).toBe('<!--v-if-->');
  });

  it('shows the healthy state: version, uptime, connected ARI, no live calls, no retry button', () => {
    const w = mountPanel({
      health: health(),
      recordings: { pending: 0, failed: 0, missing: 0 },
    });
    expect(w.text()).toContain('v0.1.9');
    expect(w.text()).toContain('1h 1m');
    expect(w.text()).toContain('Connected for 2m');
    expect(w.text()).toContain('None');
    expect(w.find('button').exists()).toBe(false);
  });

  it('flags a stale outbox and a dropped ARI session', () => {
    const w = mountPanel({
      health: health({
        outbox: { pending: 3, oldest_seconds: 400, failing: 3 },
        ari: {
          connected: false,
          connected_since: null,
          reconnects: 2,
          last_disconnect: 'close 1006',
        },
        calls_by_state: { answered: { count: 1, oldest_seconds: 95 } },
        legs_live: 2,
      }),
    });
    expect(w.text()).toContain('Pending: 3');
    expect(w.text()).toContain('6m');
    expect(w.text()).toContain('3 with failed attempts');
    expect(w.text()).toContain('Disconnected');
    expect(w.text()).toContain('Reconnects: 2');
    expect(w.text()).toContain('close 1006');
    expect(w.text()).toContain('answered: 1 · 1m');
    expect(w.text()).toContain('SIP legs up: 2');
    expect(w.html()).toContain('bg-n-ruby-3'); // outbox ≥ 5 min and ARI down
  });

  it('offers to retry when recordings are pending or failed and emits the event', async () => {
    const w = mountPanel({
      health: health(),
      recordings: { pending: 1, failed: 2, missing: 1 },
    });
    expect(w.text()).toContain('to collect: 1');
    expect(w.text()).toContain('failed: 2');
    expect(w.text()).toContain('lost: 1');
    await w.find('button').trigger('click');
    expect(w.emitted('retryRecordings')).toHaveLength(1);
  });

  it('highlights sweep counters that grew', () => {
    const w = mountPanel({
      health: health({
        counters: {
          pstn_gone: 2,
          orphan_cleanup: 0,
          bridge_failures: 1,
          recordings_missing: 0,
        },
      }),
    });
    expect(w.text()).toContain('customer vanished: 2');
    expect(w.text()).toContain('bridge failures: 1');
    expect(w.text()).toContain('worth a look');
  });
});
