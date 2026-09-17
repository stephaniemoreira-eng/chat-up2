<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ProspectingAPI from 'dashboard/api/sales/prospecting';
import LabelsAPI from 'dashboard/api/labels';
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
const hourOptions = Array.from({ length: 24 }, (_, hour) => ({
  value: hour,
  label: String(hour).padStart(2, '0'),
}));
const minuteOptions = Array.from({ length: 12 }, (_, i) => i * 5).map(
  minute => ({
    value: minute,
    label: String(minute).padStart(2, '0'),
  })
);

const { t } = useI18n();

const pipelinesStore = useSalesPipelinesStore();
const stagesStore = useSalesStagesStore();

const configs = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);
const existingLabels = ref([]);

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
  scheduledHour: 6,
  scheduledMinute: 0,
  autoContactEnabled: false,
  contactTag: '',
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

const loadExistingLabels = async () => {
  try {
    const { data } = await LabelsAPI.get();
    existingLabels.value = (data.payload || []).map(label => label.title);
  } catch {
    // Best-effort only: the field still works as free text without suggestions.
    existingLabels.value = [];
  }
};

const onPickExistingTag = title => {
  form.contactTag = title;
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
      scheduled_hour: form.scheduledHour,
      scheduled_minute: form.scheduledMinute,
      auto_contact_enabled: form.autoContactEnabled,
      contact_tag: form.contactTag.trim() || undefined,
    });
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.CREATE_SUCCESS'));
    form.businessType = '';
    form.neighborhood = '';
    form.city = '';
    form.state = null;
    form.requirePhone = false;
    form.requireWebsite = false;
    form.contactTag = '';
    await loadConfigs();
    await loadExistingLabels();
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

const onChangeScheduledHour = async (config, hour) => {
  const previous = config.scheduled_hour;
  config.scheduled_hour = hour;
  try {
    await ProspectingAPI.updateConfig(config.id, { scheduled_hour: hour });
  } catch {
    config.scheduled_hour = previous;
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.UPDATE_ERROR'));
  }
};

const onChangeScheduledMinute = async (config, minute) => {
  const previous = config.scheduled_minute;
  config.scheduled_minute = minute;
  try {
    await ProspectingAPI.updateConfig(config.id, { scheduled_minute: minute });
  } catch {
    config.scheduled_minute = previous;
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.UPDATE_ERROR'));
  }
};

const onChangeDesiredCount = async (config, count) => {
  const previous = config.desired_count;
  const clamped = Math.min(60, Math.max(1, Number(count) || 1));
  config.desired_count = clamped;
  try {
    await ProspectingAPI.updateConfig(config.id, { desired_count: clamped });
  } catch {
    config.desired_count = previous;
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.UPDATE_ERROR'));
  }
};

const onToggleAutoContact = async config => {
  const previous = config.auto_contact_enabled;
  config.auto_contact_enabled = !previous;
  try {
    await ProspectingAPI.updateConfig(config.id, {
      auto_contact_enabled: config.auto_contact_enabled,
    });
  } catch {
    config.auto_contact_enabled = previous;
    useAlert(t('CRM.PROSPECTING.AUTO_SEARCH.UPDATE_ERROR'));
  }
};

const onChangeContactTag = async (config, tag) => {
  const previous = config.contact_tag;
  const trimmed = tag.trim();
  config.contact_tag = trimmed || null;
  try {
    await ProspectingAPI.updateConfig(config.id, {
      contact_tag: trimmed || null,
    });
  } catch {
    config.contact_tag = previous;
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
  await loadExistingLabels();
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

      <div class="grid grid-cols-2 gap-3">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CRM.PROSPECTING.FORM.SCHEDULED_HOUR_LABEL') }}
          </label>
          <div class="flex items-center gap-1">
            <ComboBox
              :model-value="form.scheduledHour"
              :options="hourOptions"
              class="w-20"
              @update:model-value="value => (form.scheduledHour = value)"
            />
            <span class="text-n-slate-11">:</span>
            <ComboBox
              :model-value="form.scheduledMinute"
              :options="minuteOptions"
              class="w-20"
              @update:model-value="value => (form.scheduledMinute = value)"
            />
          </div>
          <p class="text-xs text-n-slate-11">
            {{ t('CRM.PROSPECTING.FORM.SCHEDULED_HOUR_HELP') }}
          </p>
        </div>
        <div class="flex flex-col gap-1">
          <Input
            v-model.number="form.desiredCount"
            type="number"
            min="1"
            max="60"
            :label="t('CRM.PROSPECTING.FORM.DESIRED_COUNT_LABEL')"
          />
          <span class="text-xs text-n-slate-11">
            {{ t('CRM.PROSPECTING.FORM.DESIRED_COUNT_HELP') }}
          </span>
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

      <div
        class="flex flex-col gap-1 p-3 rounded-lg border border-n-weak bg-n-solid-1"
      >
        <label
          class="flex items-center gap-2 text-sm font-medium text-n-slate-12"
        >
          <Switch v-model="form.autoContactEnabled" />
          {{ t('CRM.PROSPECTING.FORM.AUTO_CONTACT_LABEL') }}
        </label>
        <p class="text-xs text-n-slate-11">
          {{ t('CRM.PROSPECTING.FORM.AUTO_CONTACT_HELP') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <Input
          v-model="form.contactTag"
          :label="t('CRM.PROSPECTING.FORM.CONTACT_TAG_LABEL')"
          :placeholder="t('CRM.PROSPECTING.FORM.CONTACT_TAG_PLACEHOLDER')"
        />
        <p class="text-xs text-n-slate-11">
          {{ t('CRM.PROSPECTING.FORM.CONTACT_TAG_HELP') }}
        </p>
        <div
          v-if="existingLabels.length"
          class="flex flex-wrap items-center gap-1.5 mt-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ t('CRM.PROSPECTING.FORM.CONTACT_TAG_EXISTING') }}
          </span>
          <button
            v-for="label in existingLabels"
            :key="label"
            type="button"
            class="px-2 py-0.5 rounded-full text-xs border border-n-weak text-n-slate-12 hover:bg-n-solid-2"
            @click="onPickExistingTag(label)"
          >
            {{ label }}
          </button>
        </div>
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
            <div class="flex flex-col gap-1">
              <label class="text-xs text-n-slate-11">
                {{ t('CRM.PROSPECTING.AUTO_SEARCH.SCHEDULED_HOUR_LABEL') }}
              </label>
              <div class="flex items-center gap-1">
                <ComboBox
                  :model-value="config.scheduled_hour"
                  :options="hourOptions"
                  class="w-16"
                  @update:model-value="
                    value => onChangeScheduledHour(config, value)
                  "
                />
                <span class="text-n-slate-11">:</span>
                <ComboBox
                  :model-value="config.scheduled_minute"
                  :options="minuteOptions"
                  class="w-16"
                  @update:model-value="
                    value => onChangeScheduledMinute(config, value)
                  "
                />
              </div>
            </div>
            <div class="flex flex-col gap-1 w-20">
              <label class="text-xs text-n-slate-11">
                {{ t('CRM.PROSPECTING.AUTO_SEARCH.DESIRED_COUNT_LABEL') }}
              </label>
              <Input
                type="number"
                min="1"
                max="60"
                :model-value="config.desired_count"
                class="!mb-0"
                @change="
                  event => onChangeDesiredCount(config, event.target.value)
                "
              />
            </div>
            <label class="flex flex-col items-center gap-1">
              <span class="text-xs text-n-slate-11">
                {{ t('CRM.PROSPECTING.AUTO_SEARCH.AUTO_CONTACT_LABEL') }}
              </span>
              <Switch
                :model-value="config.auto_contact_enabled"
                @update:model-value="() => onToggleAutoContact(config)"
              />
            </label>
            <div class="flex flex-col gap-1 w-28">
              <label class="text-xs text-n-slate-11">
                {{ t('CRM.PROSPECTING.AUTO_SEARCH.CONTACT_TAG_LABEL') }}
              </label>
              <Input
                :model-value="config.contact_tag"
                class="!mb-0"
                :placeholder="t('CRM.PROSPECTING.FORM.CONTACT_TAG_PLACEHOLDER')"
                @change="
                  event => onChangeContactTag(config, event.target.value)
                "
              />
            </div>
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
