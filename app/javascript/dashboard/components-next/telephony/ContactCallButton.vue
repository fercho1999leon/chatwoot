<script setup>
// "Call" from the contact panel (SIP telephony): the server picks the contact's open
// conversation (or creates one in the Telephony inbox) and starts the call there.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useTelephonyStore } from 'dashboard/stores/telephony';
import { useSipSession } from 'dashboard/composables/useSipSession';
import TelephonyAPI from 'dashboard/api/telephony';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contactId: { type: [Number, String], required: true },
  phone: { type: String, default: '' },
  label: { type: String, default: '' },
});

const { t } = useI18n();
const router = useRouter();
const { accountId, isCloudFeatureEnabled } = useAccount();
const inboxes = useMapGetter('inboxes/getInboxes');
const store = useTelephonyStore();
const { connect } = useSipSession();
const isWorking = ref(false);

const shouldRender = computed(
  () =>
    !!props.phone &&
    isCloudFeatureEnabled(FEATURE_FLAGS.TELEPHONY_CALLS) &&
    inboxes.value.some(i => i.channel_type === INBOX_TYPES.TELEPHONY)
);
const isDisabled = computed(() => store.hasActiveCall || isWorking.value);

const startCall = async () => {
  if (isDisabled.value) return;
  isWorking.value = true;
  try {
    const registered = await connect();
    if (!registered) {
      useAlert(t('TELEPHONY.ERROR.REGISTER', { reason: store.sipError || '' }));
      return;
    }
    store.autoAcceptInvitation = true;
    store.idempotencyKey = store.idempotencyKey || crypto.randomUUID();
    const call = await TelephonyAPI.contactCall(
      props.contactId,
      store.idempotencyKey
    );
    store.applyCall(call, store.currentUserId);
    if (call.conversation_display_id) {
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId: accountId.value,
          conversation_id: call.conversation_display_id,
        },
      });
    }
  } catch (error) {
    store.autoAcceptInvitation = false;
    store.idempotencyKey = null;
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isWorking.value = false;
  }
};
</script>

<template>
  <NextButton
    v-if="shouldRender"
    v-bind="$attrs"
    icon="i-lucide-phone"
    :label="label"
    :disabled="isDisabled"
    :is-loading="isWorking"
    @click="startCall"
  />
</template>
