<script setup>
import { computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useTelephonyStore } from 'dashboard/stores/telephony';
import { useSipSession } from 'dashboard/composables/useSipSession';
import { useCallsStore } from 'dashboard/stores/calls';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  chat: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const store = useTelephonyStore();
const callsStore = useCallsStore();
const { isCloudFeatureEnabled } = useAccount();
const { connect } = useSipSession();

const displayId = computed(() => props.chat?.id);
const featureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.TELEPHONY_CALLS)
);
const caps = computed(() => store.capabilities[displayId.value] || null);
const isVisible = computed(() => featureEnabled.value && !!caps.value?.enabled);
const isDisabled = computed(
  () =>
    !store.canCall(displayId.value) ||
    store.isCreating ||
    callsStore.hasActiveCall ||
    callsStore.hasIncomingCall
);

const tooltip = computed(() => {
  if (store.hasActiveCall || callsStore.hasActiveCall) {
    return t('TELEPHONY.BUTTON.BUSY');
  }
  const reason = caps.value?.reason;
  if (reason) return t(`TELEPHONY.REASON.${reason.toUpperCase()}`, reason);
  return t('TELEPHONY.BUTTON.CALL', {
    destination: caps.value?.destination_masked || '',
  });
});

watch(
  () => [displayId.value, featureEnabled.value],
  ([id, enabled]) => {
    if (id && enabled) store.fetchCapabilities(id);
  },
  { immediate: true }
);

const startCall = async () => {
  if (isDisabled.value) return;
  const registered = await connect();
  if (!registered) {
    useAlert(t('TELEPHONY.ERROR.REGISTER', { reason: store.sipError || '' }));
    return;
  }
  try {
    // The agent already clicked "Call": accept the PBX's invitation for this leg without a second click.
    store.autoAcceptInvitation = true;
    await store.createCall(displayId.value);
  } catch (error) {
    store.autoAcceptInvitation = false;
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
    store.idempotencyKey = null;
  }
};
</script>

<template>
  <NextButton
    v-if="isVisible"
    v-tooltip.bottom="tooltip"
    sm
    ghost
    slate
    icon="i-lucide-phone-outgoing"
    :is-loading="store.isCreating"
    :disabled="isDisabled"
    @click="startCall"
  />
</template>
