<script setup>
// Dialpad for the Calls page (SIP telephony): dial any number (national or +E.164) or search a
// contact by name/number. The server finds (or creates) the contact and its conversation.
import { computed, ref, watch } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useDebounceFn } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useTelephonyStore } from 'dashboard/stores/telephony';
import { useSipSession } from 'dashboard/composables/useSipSession';
import ContactAPI from 'dashboard/api/contacts';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const KEYS = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '0', '#'];
const MIN_DIGITS = 7;
const MAX_SUGGESTIONS = 5;

const { t } = useI18n();
const router = useRouter();
const { accountId } = useAccount();
const store = useTelephonyStore();
const { connect } = useSipSession();

const isOpen = ref(false);
const query = ref('');
const suggestions = ref([]);
const isCalling = ref(false);
const inputRef = ref(null);

// Typed text is a number when, ignoring separators, it is only digits (optionally with a leading +).
const dialable = computed(() => {
  const compact = query.value.replace(/[\s().-]/g, '');
  return /^\+?\d+$/.test(compact) &&
    compact.replace('+', '').length >= MIN_DIGITS
    ? compact
    : '';
});
const isBusy = computed(() => store.hasActiveCall || isCalling.value);

// Contacts store numbers as +E.164: a national number (0987…) is searched without its leading 0.
const searchTerm = () => {
  const compact = query.value.replace(/[\s().-]/g, '');
  return /^0\d+$/.test(compact) ? compact.slice(1) : query.value.trim();
};

const searchContacts = useDebounceFn(async () => {
  const term = searchTerm();
  if (term.length < 3) {
    suggestions.value = [];
    return;
  }
  try {
    const { data } = await ContactAPI.search(term);
    suggestions.value = (data?.payload || [])
      .filter(contact => contact.phone_number)
      .slice(0, MAX_SUGGESTIONS);
  } catch (e) {
    suggestions.value = [];
  }
}, 300);

watch(query, searchContacts);

const toggle = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) setTimeout(() => inputRef.value?.focus(), 0);
};
const close = () => {
  isOpen.value = false;
};
const press = key => {
  query.value += key;
  inputRef.value?.focus();
};
const backspace = () => {
  query.value = query.value.slice(0, -1);
};

const call = async target => {
  if (isBusy.value) return;
  isCalling.value = true;
  try {
    const registered = await connect();
    if (!registered) {
      useAlert(t('TELEPHONY.ERROR.REGISTER', { reason: store.sipError || '' }));
      return;
    }
    const created = await store.callContact(target);
    close();
    query.value = '';
    if (created.conversation_display_id) {
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId: accountId.value,
          conversation_id: created.conversation_display_id,
        },
      });
    }
  } catch (error) {
    const code = error?.response?.data?.code || 'unknown';
    useAlert(
      t(`TELEPHONY.ERROR.${code.toUpperCase()}`, t('TELEPHONY.ERROR.UNKNOWN'))
    );
  } finally {
    isCalling.value = false;
  }
};

const callNumber = () => {
  if (dialable.value) call({ phone_number: dialable.value });
};
const callSuggestion = contact => call({ contact_id: contact.id });
</script>

<template>
  <div v-on-click-outside="close" class="relative">
    <NextButton
      sm
      solid
      blue
      icon="i-lucide-phone-outgoing"
      :label="t('CALLS_PAGE.DIALPAD.BUTTON')"
      :disabled="store.hasActiveCall"
      @click="toggle"
    />
    <div
      v-if="isOpen"
      class="absolute right-0 z-50 mt-2 w-72 p-3 flex flex-col gap-3 rounded-xl border border-n-weak bg-n-alpha-3 backdrop-blur-[100px] shadow-lg"
    >
      <div class="flex items-center gap-1">
        <input
          ref="inputRef"
          v-model="query"
          type="text"
          inputmode="tel"
          autocomplete="off"
          class="!mb-0 flex-1 text-base tabular-nums"
          :placeholder="t('CALLS_PAGE.DIALPAD.PLACEHOLDER')"
          @keydown.enter.prevent="callNumber"
          @keydown.esc="close"
        />
        <NextButton
          v-if="query"
          sm
          ghost
          slate
          icon="i-lucide-delete"
          :title="t('CALLS_PAGE.DIALPAD.DELETE')"
          @click="backspace"
        />
      </div>

      <ul v-if="suggestions.length" class="flex flex-col gap-0.5 list-none">
        <li v-for="contact in suggestions" :key="contact.id">
          <button
            type="button"
            class="w-full flex items-center gap-2 px-2 py-1.5 rounded-lg text-left hover:bg-n-alpha-2 disabled:opacity-50"
            :disabled="isBusy"
            @click="callSuggestion(contact)"
          >
            <Avatar
              :name="contact.name"
              :src="contact.thumbnail"
              :size="24"
              rounded-full
            />
            <span class="flex flex-col min-w-0">
              <span class="text-sm truncate text-n-slate-12">
                {{ contact.name }}
              </span>
              <span class="text-xs tabular-nums text-n-slate-11">
                {{ contact.phone_number }}
              </span>
            </span>
          </button>
        </li>
      </ul>

      <div class="grid grid-cols-3 gap-1">
        <NextButton
          v-for="key in KEYS"
          :key="key"
          sm
          faded
          slate
          :label="key"
          @click="press(key)"
        />
      </div>

      <NextButton
        solid
        teal
        icon="i-lucide-phone"
        class="w-full"
        :label="
          dialable
            ? t('CALLS_PAGE.DIALPAD.CALL_NUMBER', { number: dialable })
            : t('CALLS_PAGE.DIALPAD.CALL')
        "
        :disabled="!dialable || isBusy"
        :is-loading="isCalling"
        @click="callNumber"
      />
      <p class="text-xs text-n-slate-11">
        {{ t('CALLS_PAGE.DIALPAD.HINT') }}
      </p>
    </div>
  </div>
</template>
