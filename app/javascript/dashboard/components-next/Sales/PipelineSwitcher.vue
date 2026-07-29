<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  pipelines: { type: Array, default: () => [] },
  modelValue: { type: [String, Number], default: '' },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const options = computed(() =>
  props.pipelines.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
</script>

<template>
  <ComboBox
    :model-value="modelValue"
    :options="options"
    :placeholder="t('CRM.PIPELINE_SWITCHER.PLACEHOLDER')"
    @update:model-value="value => emit('update:modelValue', value)"
  />
</template>
