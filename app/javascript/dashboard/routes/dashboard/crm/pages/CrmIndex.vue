<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useSalesPipelinesStore } from 'dashboard/stores/sales/pipelines';
import { useSalesStagesStore } from 'dashboard/stores/sales/stages';
import { useSalesLeadsStore } from 'dashboard/stores/sales/leads';

import PipelineSwitcher from 'dashboard/components-next/Sales/PipelineSwitcher.vue';
import KanbanBoard from 'dashboard/components-next/Sales/Board/KanbanBoard.vue';
import BoardEmptyState from 'dashboard/components-next/Sales/Board/BoardEmptyState.vue';
import LeadCreateDialog from 'dashboard/components-next/Sales/LeadCreateDialog.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const pipelinesStore = useSalesPipelinesStore();
const stagesStore = useSalesStagesStore();
const leadsStore = useSalesLeadsStore();

const leadCreateDialogRef = ref(null);

const pipelines = computed(() => pipelinesStore.getPipelines);
const isFetchingPipelines = computed(
  () => pipelinesStore.getUIFlags.fetchingList
);
const isFetchingBoard = computed(
  () =>
    stagesStore.getUIFlags.fetchingList || leadsStore.getUIFlags.fetchingList
);
const isCreatingLead = computed(() => leadsStore.getUIFlags.creatingItem);

const activePipelineId = computed(() => {
  if (route.params.pipelineId) return Number(route.params.pipelineId);
  const defaultPipeline = pipelines.value.find(pipeline => pipeline.is_default);
  return defaultPipeline?.id || pipelines.value[0]?.id || null;
});

const activeStages = computed(() =>
  activePipelineId.value
    ? stagesStore.getStagesByPipeline(activePipelineId.value)
    : []
);

const getLeadsForStage = stageId => leadsStore.getLeadsByStage(stageId);

const loadBoard = async pipelineId => {
  if (!pipelineId) return;
  await Promise.all([
    stagesStore.get(pipelineId),
    leadsStore.get({ pipelineId }),
  ]);
};

const onSelectPipeline = pipelineId => {
  router.push({
    name: 'crm_pipeline_show',
    params: { accountId: route.params.accountId, pipelineId },
  });
};

const onMoveLead = async ({ id, salesStageId }) => {
  try {
    await leadsStore.move({ id, salesStageId });
  } catch {
    useAlert(t('CRM.LEAD.MOVE.ERROR'));
  }
};

const onAddLead = stageId => {
  leadCreateDialogRef.value?.open(stageId);
};

const onCreateLead = async leadAttrs => {
  try {
    await leadsStore.create({
      ...leadAttrs,
      pipeline_id: activePipelineId.value,
    });
    leadCreateDialogRef.value?.onSuccess();
    useAlert(t('CRM.LEAD.CREATE.MESSAGES.SUCCESS'));
  } catch {
    useAlert(t('CRM.LEAD.CREATE.MESSAGES.ERROR'));
  }
};

watch(activePipelineId, pipelineId => loadBoard(pipelineId));

onMounted(async () => {
  await pipelinesStore.get();
  loadBoard(activePipelineId.value);
});
</script>

<template>
  <div class="flex flex-col h-full min-h-0">
    <div
      class="flex items-center justify-between gap-4 p-4 border-b border-n-weak"
    >
      <span class="text-lg font-medium text-n-slate-12">{{
        t('CRM.HEADER')
      }}</span>
      <PipelineSwitcher
        v-if="pipelines.length > 1"
        :pipelines="pipelines"
        :model-value="activePipelineId"
        @update:model-value="onSelectPipeline"
      />
    </div>
    <div
      v-if="isFetchingPipelines"
      class="flex items-center justify-center p-8"
    >
      <span class="text-n-slate-11 text-base">{{ t('CRM.LOADING') }}</span>
    </div>
    <BoardEmptyState v-else-if="!activePipelineId" />
    <div v-else class="flex-1 min-h-0">
      <div v-if="isFetchingBoard" class="flex items-center justify-center p-8">
        <span class="text-n-slate-11 text-base">{{ t('CRM.LOADING') }}</span>
      </div>
      <KanbanBoard
        v-else
        :stages="activeStages"
        :get-leads-for-stage="getLeadsForStage"
        @move-lead="onMoveLead"
        @add-lead="onAddLead"
      />
    </div>
    <LeadCreateDialog
      ref="leadCreateDialogRef"
      :is-loading="isCreatingLead"
      @create="onCreateLead"
    />
  </div>
</template>
