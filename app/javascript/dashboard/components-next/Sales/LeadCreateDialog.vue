<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import ContactAPI from 'dashboard/api/contacts';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const SEARCH_DEBOUNCE_DELAY = 300;

const { t } = useI18n();
const dialogRef = ref(null);

const form = reactive({ title: '', contactId: '', value: '' });
const contactOptions = ref([]);

const isFormInvalid = computed(() => !form.title.trim() || !form.contactId);

const resetForm = () => {
  form.title = '';
  form.contactId = '';
  form.value = '';
  contactOptions.value = [];
};

const open = stageId => {
  resetForm();
  form.stageId = stageId;
  dialogRef.value?.open();
};

const searchContacts = debounce(async query => {
  if (!query) {
    contactOptions.value = [];
    return;
  }
  const { data } = await ContactAPI.search(query);
  contactOptions.value = (data.payload || []).map(contact => ({
    value: contact.id,
    label: [contact.name, contact.email].filter(Boolean).join(' · '),
  }));
}, SEARCH_DEBOUNCE_DELAY);

const handleConfirm = () => {
  if (isFormInvalid.value) return;

  emit('create', {
    title: form.title.trim(),
    contact_id: form.contactId,
    value: form.value || null,
    sales_stage_id: form.stageId,
  });
};

const closeDialog = () => dialogRef.value?.close();

const onSuccess = () => {
  resetForm();
  closeDialog();
};

defineExpose({ dialogRef, onSuccess, open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CRM.LEAD.CREATE.TITLE')"
    width="lg"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.title"
        :label="t('CRM.LEAD.CREATE.FIELDS.TITLE')"
        :placeholder="t('CRM.LEAD.CREATE.FIELDS.TITLE_PLACEHOLDER')"
        :disabled="isLoading"
        autofocus
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-11">
          {{ t('CRM.LEAD.CREATE.FIELDS.CONTACT') }}
        </label>
        <ComboBox
          use-api-results
          :model-value="form.contactId"
          :options="contactOptions"
          :disabled="isLoading"
          :search-placeholder="
            t('CRM.LEAD.CREATE.FIELDS.CONTACT_SEARCH_PLACEHOLDER')
          "
          @search="searchContacts"
          @update:model-value="value => (form.contactId = value)"
        />
      </div>
      <Input
        v-model="form.value"
        type="number"
        :label="t('CRM.LEAD.CREATE.FIELDS.VALUE')"
        :disabled="isLoading"
      />
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          :label="t('DIALOG.BUTTONS.CANCEL')"
          variant="link"
          type="reset"
          @click="closeDialog"
        />
        <Button
          :label="t('CRM.LEAD.CREATE.ACTIONS.SAVE')"
          color="blue"
          type="submit"
          :disabled="isFormInvalid || isLoading"
          :is-loading="isLoading"
        />
      </div>
    </template>
  </Dialog>
</template>
