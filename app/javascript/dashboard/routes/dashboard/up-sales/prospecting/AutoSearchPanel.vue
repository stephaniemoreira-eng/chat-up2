<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ProspectingAPI from 'dashboard/api/sales/prospecting';
import { useSalesPipelinesStore } from 'dashboard/stores/sales/pipelines';
import { useSalesStagesStore } from 'dashboard/stores/sales/stages';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const BRAZILIAN_STATES = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];
const stateOptions = BRAZILIAN_STATES.map(uf => ({ value: uf, label: uf }));

const { t } = useI18n();

const pipelinesStore = useSalesPipelinesStore();
const stagesStore = useSalesStagesStore();

const configs = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);

const form = reactive({
  businessType: '',
  neighborhood: '',
  city: '',
  state: null,
  desiredCount: 20,
  requirePhone: false,
  requireWebsite: false,
  pipelineId: null,
  stageId: null,
});

const pipelines = computed(() => pipelinesStore.getPipelines);
const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const formStages = computed(() =>
  form.pipelineId ? stagesStore.getStagesByPipeline(form.pipelineId) : []
);
const formStageOptions = computed(() =>
  formStages.value.map(stage => ({ value: stage.id, label: stage.name }))
);

const canSave = computed(
  () =>
    form.businessType.trim() &&
    form.city.trim() &&
    form.state &&
    form.pipelineId
);

const onSelectFormPipeline = id => {
  form.pipelineId = id;
  form.stageId = null;
  stagesStore.get(id);
};

const stageName = config => {
  const stages =
    stagesStore.getStagesByPipeline(config.sales_pipeline_id) || [];
  return stages.find(stage => stage.id === config.sales_stage_id)?.name || '—';
};

const pipelineName = config =>
  pipelines.value.find(pipeline => pipeline.id === config.sales_pipeline_id)
    ?.name || '—';

const locationLabel = config =>
  [config.neighborhood, config.city, config.state].filter(Boolean).join(', ');

const lastRunLabel = config =>
  config.last_run_at
    ? new Date(config.last_run_at * 1000).toLocaleString('pt-BR')
    : t('CRM.PROSPECTING.AUTO_SEARCH.NEVER_RUN');

const loadConfigs = async () => {
  isLoading.value = true;
  try {
    const { data } = await ProspectingAPI.getConfigs();
    configs.value = data.payload || [];
  } catch {
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const onCreate = async () => {
  if (!canSave.value) return;

  isSaving.value = true;
  try {
    await ProspectingAPI.createConfig({
      business_type: form.businessType.trim(),
      neighborhood: form.neighborhood.trim() || undefined,
      city: form.city.trim(),
      state: form.state,
      desired_count: form.desiredCount,
      require_phone: form.requirePhone,
      require_website: form.requireWebsite,
      pipeline_id: form.pipelineId,
      sales_stage_id: form.stageId || undefined,
    });
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.CREATE_SUCCESS'));
    form.businessType = '';
    form.neighborhood = '';
    form.city = '';
    form.state = null;
    form.requirePhone = false;
    form.requireWebsite = false;
    await loadConfigs();
  } catch {
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.CREATE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

const onToggleActive = async config => {
  const previous = config.active;
  config.active = !previous;
  try {
    await ProspectingAPI.updateConfig(config.id, { active: config.active });
  } catch {
    config.active = previous;
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.UPDATE_ERROR'));
  }
};

const onDelete = async config => {
  try {
    await ProspectingAPI.deleteConfig(config.id);
    configs.value = configs.value.filter(c => c.id !== config.id);
  } catch {
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.DELETE_ERROR'));
  }
};

onMounted(async () => {
  await pipelinesStore.get();
  await Promise.all(
    pipelines.value.map(pipeline => stagesStore.get(pipeline.id))
  );
  await loadConfigs();
});
</script>

<template>
  <div class="flex flex-col gap-6">
    <p class="text-sm text-n-slate-11 max-w-2xl">
      {{ t('CRM.PROSPECTING.AUTO_SEARCH.DESCRIPTION') }}
    </p>

    <form
      class="flex flex-col gap-4 max-w-3xl p-4 rounded-lg border border-n-weak"
      @submit.prevent="onCreate"
    >
      <Input
        v-model="form.businessType"
        :label="t('CRM.PROSPECTING.FORM.BUSINESS_TYPE_LABEL')"
        :placeholder="t('CRM.PROSPECTING.FORM.BUSINESS_TYPE_PLACEHOLDER')"
      />

      <div class="grid grid-cols-3 gap-3">
        <Input
          v-model="form.neighborhood"
          :label="t('CRM.PROSPECTING.FORM.NEIGHBORHOOD_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.NEIGHBORHOOD_PLACEHOLDER')"
        />
        <Input
          v-model="form.city"
          :label="t('CRM.PROSPECTING.FORM.CITY_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.CITY_PLACEHOLDER')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.STATE_LABEL') }}
          </label>
          <ComboBox
            :model-value="form.state"
            :options="stateOptions"
            :placeholder="t('CRM.PROSPECTING.FORM.STATE_PLACEHOLDER')"
            @update:model-value="value => (form.state = value)"
          />
        </div>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PIPELINE_SWITCHER.PLACEHOLDER') }}
          </label>
          <ComboBox
            :model-value="form.pipelineId"
            :options="pipelineOptions"
            @update:model-value="onSelectFormPipeline"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.CREATE.STAGE_PLACEHOLDER') }}
          </label>
          <ComboBox
            :model-value="form.stageId"
            :options="formStageOptions"
            @update:model-value="value => (form.stageId = value)"
          />
        </div>
      </div>

      <div class="flex items-center gap-6">
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.requirePhone" />
          {{ t('CRM.PROSPECTING.FORM.REQUIRE_PHONE_LABEL') }}
        </label>
        <label class="flex items-center gap-2 text-sm text-n-slate-12">
          <Switch v-model="form.requireWebsite" />
          {{ t('CRM.PROSPECTING.FORM.REQUIRE_WEBSITE_LABEL') }}
        </label>
      </div>

      <Button
        type="submit"
        class="self-end"
        :label="t('CRM.PROSPECTING.AUTO_SEARCH.ADD_ACTION')"
        :is-loading="isSaving"
        :disabled="!canSave"
      />
    </form>

    <div class="flex flex-col gap-2">
      <div v-if="isLoading" class="text-sm text-n-slate-11">
        {{ t('CRM.PROSPECTING.AUTO_SEARCH.LOADING') }}
      </div>
      <div v-else-if="configs.length === 0" class="text-sm text-n-slate-11">
        {{ t('CRM.PROSPECTING.AUTO_SEARCH.EMPTY') }}
      </div>
      <template v-else>
        <div
          v-for="config in configs"
          :key="config.id"
          class="flex items-center justify-between gap-3 p-3 rounded-lg border border-n-weak bg-n-solid-1"
        >
          <div class="flex flex-col min-w-0">
            <span class="text-sm font-medium text-n-slate-12">
              {{ config.business_type }}
            </span>
            <span class="text-xs text-n-slate-11">{{
              locationLabel(config)
            }}</span>
            <span class="text-xs text-n-slate-11">
              {{
                t('CRM.PROSPECTING.AUTO_SEARCH.PIPELINE_STAGE', {
                  pipeline: pipelineName(config),
                  stage: stageName(config),
                })
              }}
            </span>
            <span class="text-xs text-n-slate-10">
              {{
                t('CRM.PROSPECTING.AUTO_SEARCH.LAST_RUN_AT', {
                  when: lastRunLabel(config),
                })
              }}
            </span>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <Switch
              :model-value="config.active"
              @update:model-value="() => onToggleActive(config)"
            />
            <Button
              icon="i-lucide-trash"
              color="ruby"
              variant="ghost"
              size="sm"
              @click="onDelete(config)"
            />
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
