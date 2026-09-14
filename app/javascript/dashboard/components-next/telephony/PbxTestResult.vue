<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ result: { type: Object, default: null } });
const { t } = useI18n();
</script>

<template>
  <div v-if="result" class="flex flex-wrap gap-2 text-sm">
    <span
      class="px-2 py-0.5 rounded-full"
      :class="
        result.ari?.ok
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-ruby-3 text-n-ruby-11'
      "
    >
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.ARI_TITLE') }}:
      {{
        result.ari?.ok
          ? `${t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST.OK')} (Asterisk ${result.ari.version})`
          : result.ari?.error
      }}
    </span>
    <span
      class="px-2 py-0.5 rounded-full"
      :class="
        result.provisioner?.ok
          ? 'bg-n-teal-3 text-n-teal-11'
          : 'bg-n-ruby-3 text-n-ruby-11'
      "
    >
      {{ t('INBOX_MGMT.ADD.TELEPHONY.PBX.PROVISION_TITLE') }}:
      {{
        result.provisioner?.error === 'not_configured'
          ? t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST.NOT_CONFIGURED')
          : result.provisioner?.ok
            ? t('INBOX_MGMT.ADD.TELEPHONY.PBX.TEST.OK')
            : result.provisioner?.error
      }}
    </span>
  </div>
</template>
