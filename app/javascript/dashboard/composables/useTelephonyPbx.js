// Carga/guarda/prueba la conexión PBX de la cuenta (Settings → Inboxes → Telephony y alta del inbox).
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import TelephonyAPI from 'dashboard/api/telephony';

export const EMPTY_PBX = {
  ari_url: '',
  ari_user: 'chatwoot',
  ari_password: '',
  ari_app: 'chatwoot',
  sip_ws_url: '',
  sip_domain: '',
  stun_url: '',
  turn_urls: '',
  turn_secret: '',
  turn_ttl_seconds: 3600,
  provision_url: '',
  provision_token: '',
  test_dial: '',
  agent_timeout: 30,
  transfer_timeout: 30,
  pstn_timeout: 45,
  max_call_seconds: 3600,
  record_calls: 'never',
  recording_retention_days: 0,
  bot_webhook_url: '',
};

export const useTelephonyPbx = () => {
  const { t } = useI18n();
  const pbx = ref({ ...EMPTY_PBX });
  const configured = ref(false);
  const loading = ref(false);
  const saving = ref(false);
  const testing = ref(false);
  const testResult = ref(null);

  const errorMessage = e => {
    const code = e?.response?.data?.code || 'unknown';
    return t(
      `INBOX_MGMT.ADD.TELEPHONY.PBX.ERROR.${code.toUpperCase()}`,
      t('INBOX_MGMT.ADD.TELEPHONY.PBX.ERROR.UNKNOWN')
    );
  };

  const load = async () => {
    loading.value = true;
    try {
      const data = await TelephonyAPI.pbx();
      pbx.value = { ...EMPTY_PBX, ...data };
      configured.value = Boolean(data.configured);
    } catch (e) {
      useAlert(errorMessage(e));
    } finally {
      loading.value = false;
    }
  };

  const save = async () => {
    saving.value = true;
    try {
      const data = await TelephonyAPI.updatePbx(pbx.value);
      pbx.value = { ...EMPTY_PBX, ...data };
      configured.value = Boolean(data.configured);
      useAlert(t('INBOX_MGMT.ADD.TELEPHONY.PBX.SAVED'));
      return true;
    } catch (e) {
      useAlert(errorMessage(e));
      return false;
    } finally {
      saving.value = false;
    }
  };

  const test = async () => {
    testing.value = true;
    testResult.value = null;
    try {
      testResult.value = await TelephonyAPI.testPbx(pbx.value);
    } catch (e) {
      useAlert(errorMessage(e));
    } finally {
      testing.value = false;
    }
  };

  return {
    pbx,
    configured,
    loading,
    saving,
    testing,
    testResult,
    load,
    save,
    test,
  };
};
