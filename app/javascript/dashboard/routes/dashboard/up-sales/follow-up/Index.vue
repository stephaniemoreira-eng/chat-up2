<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import FollowUpAPI from 'dashboard/api/sales/followUp';
import { useSalesPipelinesStore } from 'dashboard/stores/sales/pipelines';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import ContactImportDialog from 'dashboard/components-next/Contacts/ContactsForm/ContactImportDialog.vue';

const { t } = useI18n();
const store = useStore();

const pipelinesStore = useSalesPipelinesStore();
const teams = useMapGetter('teams/getTeams');

const pipelineId = ref(null);
const teamId = ref(null);
const label = ref('');

const isLoading = ref(true);
const isSaving = ref(false);
const isSyncing = ref(false);
const syncResult = ref(null);

const importDialogRef = ref(null);

const pipelines = computed(() => pipelinesStore.getPipelines);
const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const teamOptions = computed(() =>
  teams.value.map(team => ({ value: team.id, label: team.name }))
);

const isConfigured = computed(() => pipelineId.value && teamId.value);

const onSave = async () => {
  isSaving.value = true;
  try {
    await FollowUpAPI.updateConfig({
      follow_up_pipeline_id: pipelineId.value,
      follow_up_team_id: teamId.value,
      follow_up_label: label.value.trim(),
    });
    useAlert(t('CRM.FOLLOW_UP.CONFIG.SUCCESS'));
  } catch {
    useAlert(t('CRM.FOLLOW_UP.CONFIG.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const onImport = async file => {
  try {
    await store.dispatch('contacts/import', file);
    importDialogRef.value?.dialogRef.close();
    useAlert(t('CRM.FOLLOW_UP.IMPORT.SUCCESS'));
  } catch {
    useAlert(t('CRM.FOLLOW_UP.IMPORT.ERROR'));
  }
};

const onSync = async () => {
  isSyncing.value = true;
  syncResult.value = null;
  try {
    const { data } = await FollowUpAPI.sync();
    syncResult.value = data;
  } catch {
    useAlert(t('CRM.FOLLOW_UP.SYNC.ERROR'));
  } finally {
    isSyncing.value = false;
  }
};

onMounted(async () => {
  await Promise.all([
    pipelinesStore.get(),
    store.dispatch('teams/get'),
    FollowUpAPI.get().then(({ data }) => {
      pipelineId.value = data.follow_up_pipeline_id
        ? Number(data.follow_up_pipeline_id)
        : null;
      teamId.value = data.follow_up_team_id
        ? Number(data.follow_up_team_id)
        : null;
      label.value = data.follow_up_label || '';
    }),
  ]);
  isLoading.value = false;
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0 overflow-y-auto p-6 gap-6">
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('CRM.FOLLOW_UP.TITLE') }}
    </h1>

    <div v-if="!isLoading" class="flex flex-col gap-6 max-w-2xl">
      <section class="flex flex-col gap-4">
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM.FOLLOW_UP.CONFIG.TITLE') }}
        </h2>

        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CRM.FOLLOW_UP.CONFIG.PIPELINE_LABEL') }}
            </label>
            <ComboBox
              :model-value="pipelineId"
              :options="pipelineOptions"
              :placeholder="t('CRM.PIPELINE_SWITCHER.PLACEHOLDER')"
              @update:model-value="value => (pipelineId = value)"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-sm font-medium text-n-slate-12">
              {{ t('CRM.FOLLOW_UP.CONFIG.TEAM_LABEL') }}
            </label>
            <ComboBox
              :model-value="teamId"
              :options="teamOptions"
              :placeholder="t('CRM.FOLLOW_UP.CONFIG.TEAM_PLACEHOLDER')"
              @update:model-value="value => (teamId = value)"
            />
          </div>
        </div>

        <Input
          v-model="label"
          :label="t('CRM.FOLLOW_UP.CONFIG.LABEL_FIELD_LABEL')"
          :placeholder="t('CRM.FOLLOW_UP.CONFIG.LABEL_FIELD_PLACEHOLDER')"
        />

        <Button
          class="self-end"
          :label="t('CRM.FOLLOW_UP.CONFIG.SAVE')"
          :is-loading="isSaving"
          @click="onSave"
        />
      </section>

      <section class="flex flex-col gap-3 pt-4 border-t border-n-weak">
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM.FOLLOW_UP.IMPORT.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11">
          {{ t('CRM.FOLLOW_UP.IMPORT.DESCRIPTION') }}
        </p>
        <Button
          class="self-start"
          :label="t('CRM.FOLLOW_UP.IMPORT.ACTION')"
          icon="i-lucide-upload"
          variant="faded"
          @click="importDialogRef?.dialogRef.open()"
        />
      </section>

      <section class="flex flex-col gap-3 pt-4 border-t border-n-weak">
        <h2 class="text-sm font-semibold text-n-slate-12">
          {{ t('CRM.FOLLOW_UP.SYNC.TITLE') }}
        </h2>
        <p class="text-xs text-n-slate-11">
          {{ t('CRM.FOLLOW_UP.SYNC.DESCRIPTION') }}
        </p>
        <Button
          class="self-start"
          :label="t('CRM.FOLLOW_UP.SYNC.ACTION')"
          :is-loading="isSyncing"
          :disabled="!isConfigured"
          @click="onSync"
        />
        <p v-if="syncResult" class="text-sm text-n-slate-12">
          {{
            t('CRM.FOLLOW_UP.SYNC.RESULT', {
              created: syncResult.created,
              assigned: syncResult.assigned,
            })
          }}
        </p>
      </section>
    </div>

    <ContactImportDialog ref="importDialogRef" @import="onImport" />
  </div>
</template>
