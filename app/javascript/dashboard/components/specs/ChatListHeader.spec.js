import { shallowMount } from '@vue/test-utils';
import ChatListHeader from '../ChatListHeader.vue';

vi.mock('dashboard/composables/useUISettings', async () => {
  const { ref } = await import('vue');
  return {
    useUISettings: () => ({
      uiSettings: ref({}),
      updateUISettings: vi.fn(),
    }),
  };
});

const { adminState } = vi.hoisted(() => ({ adminState: { isAdmin: true } }));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return {
    useAdmin: () => ({ isAdmin: computed(() => adminState.isAdmin) }),
  };
});

const mountHeader = props =>
  shallowMount(ChatListHeader, {
    props: {
      pageTitle: 'Conversations',
      hasAppliedFilters: false,
      hasActiveFolders: false,
      activeStatus: 'open',
      isOnExpandedLayout: false,
      conversationStats: { allCount: 12 },
      isListLoading: false,
      ...props,
    },
    global: {
      mocks: { $t: key => key },
    },
  });

const contactFilter = { id: 7, name: 'Jane Doe' };

describe('ChatListHeader', () => {
  beforeEach(() => {
    adminState.isAdmin = true;
  });

  it('renders the page title and the filter button without filters', () => {
    const wrapper = mountHeader();

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(false);
  });

  it('keeps the page title and the filter button for non contact filters', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('names the contact and hides the filter button when scoped to a contact', () => {
    const wrapper = mountHeader({ hasAppliedFilters: true, contactFilter });

    expect(wrapper.find('h1').text()).toBe('Jane Doe');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
    expect(wrapper.find('[icon="i-lucide-chevron-left"]').exists()).toBe(true);
  });

  it('falls back to the page title when the scoped contact has no name', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      contactFilter: { id: 7, name: '' },
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('#toggleConversationFilterButton').exists()).toBe(
      false
    );
  });

  it('shows the dataset export button only for administrators', () => {
    expect(mountHeader().find('[icon="i-lucide-download"]').exists()).toBe(
      true
    );

    adminState.isAdmin = false;

    expect(mountHeader().find('[icon="i-lucide-download"]').exists()).toBe(
      false
    );
  });

  it('keeps the folder controls when a folder is active', () => {
    const wrapper = mountHeader({
      hasAppliedFilters: true,
      hasActiveFolders: true,
      contactFilter,
    });

    expect(wrapper.find('h1').text()).toBe('Conversations');
    expect(wrapper.find('[icon="i-lucide-pen-line"]').exists()).toBe(true);
    expect(wrapper.find('[icon="i-lucide-trash-2"]').exists()).toBe(true);
  });
});
