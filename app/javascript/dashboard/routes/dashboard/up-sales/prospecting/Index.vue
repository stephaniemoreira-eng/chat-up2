<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ProspectingAPI from 'dashboard/api/sales/prospecting';
import { useSalesPipelinesStore } from 'dashboard/stores/sales/pipelines';
import { useSalesStagesStore } from 'dashboard/stores/sales/stages';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const { t } = useI18n();

const pipelinesStore = useSalesPipelinesStore();
const stagesStore = useSalesStagesStore();

const businessType = ref('');
const location = ref('');
const isSearching = ref(false);
const isSaving = ref(false);
const results = ref([]);
const selectedIds = ref(new Set());
const hasSearched = ref(false);

const pipelineId = ref(null);
const stageId = ref(null);

const pipelines = computed(() => pipelinesStore.getPipelines);
const pipelineOptions = computed(() =>
  pipelines.value.map(pipeline => ({
    value: pipeline.id,
    label: pipeline.name,
  }))
);
const stages = computed(() =>
  pipelineId.value ? stagesStore.getStagesByPipeline(pipelineId.value) : []
);
const stageOptions = computed(() =>
  stages.value.map(stage => ({ value: stage.id, label: stage.name }))
);

const selectedCount = computed(() => selectedIds.value.size);
const canAddLeads = computed(() => selectedCount.value > 0 && pipelineId.value);
const canSearch = computed(
  () => businessType.value.trim() && location.value.trim()
);
const searchQuery = computed(() =>
  t('CRM.PROSPECTING.SEARCH.QUERY_TEMPLATE', {
    type: businessType.value.trim(),
    location: location.value.trim(),
  })
);

const toggleResult = placeId => {
  const next = new Set(selectedIds.value);
  if (next.has(placeId)) {
    next.delete(placeId);
  } else {
    next.add(placeId);
  }
  selectedIds.value = next;
};

const onSelectPipeline = id => {
  pipelineId.value = id;
  stageId.value = null;
  stagesStore.get(id);
};

const onSearch = async () => {
  if (!canSearch.value) return;

  isSearching.value = true;
  hasSearched.value = true;
  selectedIds.value = new Set();
  try {
    const { data } = await ProspectingAPI.search(searchQuery.value);
    results.value = data.payload || [];
  } catch {
    useAlert(t('CRM.PROSPECTING.SEARCH.ERROR'));
    results.value = [];
  } finally {
    isSearching.value = false;
  }
};

const onAddLeads = async () => {
  const selectedResults = results.value.filter(result =>
    selectedIds.value.has(result.place_id)
  );

  isSaving.value = true;
  try {
    await ProspectingAPI.createLeads({
      pipelineId: pipelineId.value,
      salesStageId: stageId.value,
      results: selectedResults,
    });
    useAlert(
      t('CRM.PROSPECTING.CREATE.SUCCESS', { n: selectedResults.length })
    );
    results.value = results.value.filter(
      result => !selectedIds.value.has(result.place_id)
    );
    selectedIds.value = new Set();
  } catch {
    useAlert(t('CRM.PROSPECTING.CREATE.ERROR'));
  } finally {
    isSaving.value = false;
  }
};

onMounted(async () => {
  await pipelinesStore.get();
  const defaultPipeline =
    pipelines.value.find(pipeline => pipeline.is_default) || pipelines.value[0];
  if (defaultPipeline) onSelectPipeline(defaultPipeline.id);
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0 overflow-y-auto p-6 gap-6">
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('CRM.PROSPECTING.TITLE') }}
    </h1>

    <form
      class="flex items-end gap-3 flex-wrap max-w-3xl"
      @submit.prevent="onSearch"
    >
      <Input
        v-model="businessType"
        class="flex-1 min-w-[220px]"
        :label="t('CRM.PROSPECTING.SEARCH.TYPE_LABEL')"
        :placeholder="t('CRM.PROSPECTING.SEARCH.TYPE_PLACEHOLDER')"
      />
      <Input
        v-model="location"
        class="flex-1 min-w-[220px]"
        :label="t('CRM.PROSPECTING.SEARCH.LOCATION_LABEL')"
        :placeholder="t('CRM.PROSPECTING.SEARCH.LOCATION_PLACEHOLDER')"
      />
      <Button
        type="submit"
        :label="t('CRM.PROSPECTING.SEARCH.ACTION')"
        :is-loading="isSearching"
        :disabled="!canSearch"
      />
    </form>

    <div v-if="hasSearched && !isSearching" class="flex flex-col gap-4">
      <div v-if="results.length === 0" class="text-sm text-n-slate-11">
        {{ t('CRM.PROSPECTING.SEARCH.EMPTY') }}
      </div>

      <template v-else>
        <div class="flex items-center gap-3 flex-wrap">
          <ComboBox
            :model-value="pipelineId"
            :options="pipelineOptions"
            :placeholder="t('CRM.PIPELINE_SWITCHER.PLACEHOLDER')"
            class="w-56"
            @update:model-value="onSelectPipeline"
          />
          <ComboBox
            :model-value="stageId"
            :options="stageOptions"
            :placeholder="t('CRM.PROSPECTING.CREATE.STAGE_PLACEHOLDER')"
            class="w-56"
            @update:model-value="value => (stageId = value)"
          />
          <Button
            :label="t('CRM.PROSPECTING.CREATE.ACTION', { n: selectedCount })"
            :disabled="!canAddLeads"
            :is-loading="isSaving"
            @click="onAddLeads"
          />
        </div>

        <div class="flex flex-col gap-2">
          <label
            v-for="result in results"
            :key="result.place_id"
            class="flex items-start gap-3 p-3 rounded-lg border border-n-weak bg-n-solid-1 cursor-pointer"
          >
            <input
              type="checkbox"
              class="mt-1"
              :checked="selectedIds.has(result.place_id)"
              @change="toggleResult(result.place_id)"
            />
            <div class="flex flex-col min-w-0">
              <span class="text-sm font-medium text-n-slate-12">
                {{ result.name }}
              </span>
              <span class="text-xs text-n-slate-11">{{ result.address }}</span>
              <span v-if="result.phone_number" class="text-xs text-n-slate-11">
                {{ result.phone_number }}
              </span>
            </div>
          </label>
        </div>
      </template>
    </div>
  </div>
</template>
