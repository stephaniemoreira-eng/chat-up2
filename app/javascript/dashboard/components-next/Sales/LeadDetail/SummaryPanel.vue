<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  summary: { type: String, default: '' },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();
const draft = ref(props.summary || '');

watch(
  () => props.summary,
  value => {
    draft.value = value || '';
  }
);

const isDirty = computed(() => draft.value !== (props.summary || ''));

const save = () => {
  if (!isDirty.value) return;
  emit('save', draft.value);
};
</script>

<template>
  <div class="flex flex-col gap-2">
    <label class="text-sm font-medium text-n-slate-11">
      {{ t('CRM.LEAD.DETAIL.SUMMARY.LABEL') }}
    </label>
    <textarea
      v-model="draft"
      rows="4"
      class="w-full p-2 text-sm border rounded-lg resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-brand"
      :placeholder="t('CRM.LEAD.DETAIL.SUMMARY.PLACEHOLDER')"
      :disabled="isSaving"
    />
    <div class="flex justify-end">
      <Button
        :label="t('CRM.LEAD.DETAIL.SUMMARY.SAVE')"
        size="sm"
        color="blue"
        :is-loading="isSaving"
        :disabled="isSaving || !isDirty"
        @click="save"
      />
    </div>
  </div>
</template>
