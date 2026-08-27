<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
  isDeleting: { type: Boolean, default: false },
});

const emit = defineEmits(['save', 'delete']);

const { t } = useI18n();
const dialogRef = ref(null);

const DEFAULT_COLOR = '#2781F6';

const stageId = ref(null);
const name = ref('');
const color = ref(DEFAULT_COLOR);
const confirmingDelete = ref(false);

const isEditMode = computed(() => Boolean(stageId.value));
const isNameInvalid = computed(() => !name.value.trim());

const resetForm = () => {
  stageId.value = null;
  name.value = '';
  color.value = DEFAULT_COLOR;
  confirmingDelete.value = false;
};

const open = (stage = null) => {
  resetForm();
  if (stage) {
    stageId.value = stage.id;
    name.value = stage.name;
    color.value = stage.color || DEFAULT_COLOR;
  }
  dialogRef.value?.open();
};

const closeDialog = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isNameInvalid.value) return;
  emit('save', {
    id: stageId.value,
    name: name.value.trim(),
    color: color.value,
  });
};

const handleDelete = () => {
  if (!confirmingDelete.value) {
    confirmingDelete.value = true;
    return;
  }
  emit('delete', stageId.value);
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
    :title="
      isEditMode
        ? t('CRM.STAGE.EDIT.TITLE')
        : t('CRM.STAGE.CREATE.TITLE')
    "
    width="sm"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="name"
        :label="t('CRM.STAGE.FIELDS.NAME')"
        :placeholder="t('CRM.STAGE.FIELDS.NAME_PLACEHOLDER')"
        :disabled="isLoading"
        autofocus
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-11">
          {{ t('CRM.STAGE.FIELDS.COLOR') }}
        </label>
        <div class="flex items-center gap-3">
          <input
            v-model="color"
            type="color"
            class="h-9 w-9 rounded border border-n-weak cursor-pointer"
          />
          <woot-input v-model="color" type="text" class="!mb-0 w-32" />
        </div>
      </div>
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          v-if="isEditMode"
          :label="
            confirmingDelete
              ? t('CRM.STAGE.EDIT.CONFIRM_DELETE')
              : t('CRM.STAGE.EDIT.DELETE')
          "
          variant="faded"
          color="ruby"
          type="button"
          :is-loading="isDeleting"
          @click="handleDelete"
        />
        <div v-else />
        <div class="flex items-center gap-3">
          <Button
            :label="t('DIALOG.BUTTONS.CANCEL')"
            variant="link"
            type="button"
            @click="closeDialog"
          />
          <Button
            :label="t('CRM.STAGE.FIELDS.SAVE')"
            color="blue"
            type="submit"
            :disabled="isNameInvalid || isLoading"
            :is-loading="isLoading"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
