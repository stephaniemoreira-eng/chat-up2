<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['save']);

const { t } = useI18n();

const dialogRef = ref(null);

const summary = ref('');
const startsAt = ref('');
const endsAt = ref('');
const description = ref('');

const reset = () => {
  summary.value = '';
  startsAt.value = '';
  endsAt.value = '';
  description.value = '';
};

const open = () => {
  reset();
  dialogRef.value?.open();
};

const onSuccess = () => {
  dialogRef.value?.close();
};

// <input type="datetime-local"> yields "YYYY-MM-DDTHH:mm" (no seconds, no offset). The backend
// pairs whatever we send here with the integration's own configured timezone, so a bare local
// wall-clock string is enough -- just pad seconds so it's valid RFC 3339.
const withSeconds = value =>
  value && value.length === 16 ? `${value}:00` : value;

const onConfirm = () => {
  emit('save', {
    summary: summary.value.trim(),
    start: withSeconds(startsAt.value),
    end: withSeconds(endsAt.value),
    description: description.value.trim() || undefined,
  });
};

defineExpose({ dialogRef, open, onSuccess });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CRM.SCHEDULE.TITLE')"
    :description="t('CRM.SCHEDULE.DESCRIPTION')"
    :confirm-button-label="t('CRM.SCHEDULE.ACTION')"
    :disable-confirm-button="
      !summary.trim() || !startsAt || !endsAt || props.isLoading
    "
    :is-loading="props.isLoading"
    @confirm="onConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="summary"
        :label="t('CRM.SCHEDULE.FIELDS.SUMMARY')"
        :placeholder="t('CRM.SCHEDULE.FIELDS.SUMMARY_PLACEHOLDER')"
      />
      <div class="grid grid-cols-2 gap-3">
        <Input
          v-model="startsAt"
          type="datetime-local"
          :label="t('CRM.SCHEDULE.FIELDS.START')"
        />
        <Input
          v-model="endsAt"
          type="datetime-local"
          :label="t('CRM.SCHEDULE.FIELDS.END')"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CRM.SCHEDULE.FIELDS.DESCRIPTION') }}
        </label>
        <textarea
          v-model="description"
          rows="3"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
        />
      </div>
    </div>
  </Dialog>
</template>
