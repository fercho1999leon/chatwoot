<script setup>
// Bulk "set priority" dropdown: same options as the conversation header (none/urgent/high/medium/low).
import { useTemplateRef, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

const emit = defineEmits(['select']);

const { t } = useI18n();

const containerRef = useTemplateRef('containerRef');
const [showDropdown, toggleDropdown] = useToggle(false);

const PRIORITIES = [
  { value: 'urgent', icon: 'i-lucide-flame' },
  { value: 'high', icon: 'i-lucide-arrow-up' },
  { value: 'medium', icon: 'i-lucide-minus' },
  { value: 'low', icon: 'i-lucide-arrow-down' },
  { value: null, icon: 'i-lucide-circle-slash' },
];

const menuItems = computed(() =>
  PRIORITIES.map(({ value, icon }) => ({
    action: 'priority',
    value,
    icon,
    label: t(
      `CONVERSATION.PRIORITY.OPTIONS.${value ? value.toUpperCase() : 'NONE'}`
    ),
  }))
);

const handleSelect = item => {
  emit('select', item.value);
  toggleDropdown(false);
};
</script>

<template>
  <div ref="containerRef" class="relative">
    <Button
      v-tooltip="$t('BULK_ACTION.PRIORITY.CHANGE_PRIORITY')"
      icon="i-lucide-flag"
      slate
      xs
      ghost
      :class="{ 'bg-n-alpha-2': showDropdown }"
      @click="toggleDropdown()"
    />
    <Transition
      enter-active-class="transition-all duration-150 ease-out origin-bottom"
      enter-from-class="opacity-0 scale-95"
      enter-to-class="opacity-100 scale-100"
      leave-active-class="transition-all duration-100 ease-in origin-bottom"
      leave-from-class="opacity-100 scale-100"
      leave-to-class="opacity-0 scale-95"
    >
      <DropdownMenu
        v-if="showDropdown"
        v-on-click-outside="[
          () => toggleDropdown(false),
          { ignore: [containerRef] },
        ]"
        :menu-items="menuItems"
        class="ltr:-right-[4.5rem] rtl:-left-[4.5rem] ltr:2xl:right-0 rtl:2xl:left-0 bottom-8 w-36"
        @action="handleSelect"
      />
    </Transition>
  </div>
</template>
