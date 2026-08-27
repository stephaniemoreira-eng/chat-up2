<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const { t } = useI18n();
const dialogRef = ref(null);
const name = ref('');

const isNameInvalid = computed(() => !name.value.trim());

const resetForm = () => {
  name.value = '';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const closeDialog = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isNameInvalid.value) return;
  emit('create', { name: name.value.trim() });
};

const onSuccess = () => {
  resetForm();
  closeDialog();
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CRM.PIPELINE.CREATE.TITLE')"
    width="sm"
    :confirm-button-label="t('CRM.PIPELINE.CREATE.ACTION')"
    :disable-confirm-button="isNameInvalid"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <Input
      v-model="name"
      :label="t('CRM.PIPELINE.CREATE.FIELDS.NAME')"
      :placeholder="t('CRM.PIPELINE.CREATE.FIELDS.NAME_PLACEHOLDER')"
      :disabled="isLoading"
      autofocus
    />
  </Dialog>
</template>
