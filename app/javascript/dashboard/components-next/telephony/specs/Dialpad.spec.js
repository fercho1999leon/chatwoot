import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Dialpad from '../Dialpad.vue';
import calls from 'dashboard/i18n/locale/en/calls.json';
import telephony from 'dashboard/i18n/locale/en/telephony.json';
import ContactAPI from 'dashboard/api/contacts';
import { useAlert } from 'dashboard/composables';

const push = vi.fn();
const connect = vi.fn();
const store = {
  hasActiveCall: false,
  sipError: null,
  callContact: vi.fn(),
};

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', async () => {
  const { ref } = await import('vue');
  return { useAccount: () => ({ accountId: ref(1) }) };
});
vi.mock('dashboard/composables/useSipSession', () => ({
  useSipSession: () => ({ connect }),
}));
vi.mock('dashboard/stores/telephony', () => ({
  useTelephonyStore: () => store,
}));
vi.mock('dashboard/api/contacts', () => ({ default: { search: vi.fn() } }));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useDebounceFn: fn => fn,
}));

const mountDialpad = () =>
  mount(Dialpad, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'en',
          messages: { en: { ...calls, ...telephony } },
        }),
      ],
      stubs: {
        Avatar: true,
        NextButton: {
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
          props: ['label', 'disabled'],
          emits: ['click'],
        },
      },
    },
  });

const open = async wrapper => {
  await wrapper.find('button').trigger('click');
  return wrapper;
};
const callButton = wrapper =>
  wrapper.findAll('button').find(b => b.text().startsWith('Call'));

describe('Dialpad', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    store.hasActiveCall = false;
    connect.mockResolvedValue(true);
    ContactAPI.search.mockResolvedValue({ data: { payload: [] } });
  });

  it('builds the number with the keypad and dials it', async () => {
    store.callContact.mockResolvedValue({ conversation_display_id: 42 });
    const wrapper = await open(mountDialpad());

    const keys = ['0', '9', '8', '7', '6', '5', '4', '3', '2', '1'];
    // eslint-disable-next-line no-restricted-syntax
    for (const key of keys) {
      // eslint-disable-next-line no-await-in-loop
      await wrapper
        .findAll('button')
        .find(b => b.text() === key)
        .trigger('click');
    }
    expect(callButton(wrapper).text()).toBe('Call 0987654321');

    await callButton(wrapper).trigger('click');
    await flushPromises();

    expect(connect).toHaveBeenCalled();
    expect(store.callContact).toHaveBeenCalledWith({
      phone_number: '0987654321',
    });
    expect(push).toHaveBeenCalledWith({
      name: 'inbox_conversation',
      params: { accountId: 1, conversation_id: 42 },
    });
  });

  it('keeps the call button disabled until the text is a number', async () => {
    const wrapper = await open(mountDialpad());

    await wrapper.find('input').setValue('Juan');
    expect(callButton(wrapper).attributes('disabled')).toBeDefined();

    await wrapper.find('input').setValue('12345');
    expect(callButton(wrapper).attributes('disabled')).toBeDefined();

    await wrapper.find('input').setValue('+593 98 765 4321');
    expect(callButton(wrapper).attributes('disabled')).toBeUndefined();
    expect(callButton(wrapper).text()).toBe('Call +593987654321');
  });

  it('suggests contacts and calls the chosen one by id', async () => {
    ContactAPI.search.mockResolvedValue({
      data: {
        payload: [
          { id: 7, name: 'Juan Pérez', phone_number: '+593987654321' },
          { id: 8, name: 'Juana sin teléfono', phone_number: null },
        ],
      },
    });
    store.callContact.mockResolvedValue({});
    const wrapper = await open(mountDialpad());

    await wrapper.find('input').setValue('0987');
    await flushPromises();

    expect(ContactAPI.search).toHaveBeenLastCalledWith('987');
    const items = wrapper.findAll('li button');
    expect(items).toHaveLength(1);
    expect(items[0].text()).toContain('Juan Pérez');

    await items[0].trigger('click');
    await flushPromises();
    expect(store.callContact).toHaveBeenCalledWith({ contact_id: 7 });
  });

  it('shows the server error and does not navigate', async () => {
    store.callContact.mockRejectedValue({
      response: { data: { code: 'invalid_phone' } },
    });
    const wrapper = await open(mountDialpad());

    await wrapper.find('input').setValue('0987654321');
    await wrapper.find('input').trigger('keydown.enter');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      telephony.TELEPHONY.ERROR.INVALID_PHONE
    );
    expect(push).not.toHaveBeenCalled();
  });

  it('does not dial when the softphone cannot register', async () => {
    connect.mockResolvedValue(false);
    const wrapper = await open(mountDialpad());

    await wrapper.find('input').setValue('0987654321');
    await callButton(wrapper).trigger('click');
    await flushPromises();

    expect(store.callContact).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalled();
  });
});
