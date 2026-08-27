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
import LeadDetailDialog from 'dashboard/components-next/Sales/LeadDetail/LeadDetailDialog.vue';
import StageDialog from 'dashboard/components-next/Sales/StageDialog.vue';
import PipelineCreateDialog from 'dashboard/components-next/Sales/PipelineCreateDialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const pipelinesStore = useSalesPipelinesStore();
const stagesStore = useSalesStagesStore();
const leadsStore = useSalesLeadsStore();

const leadCreateDialogRef = ref(null);
const leadDetailDialogRef = ref(null);
const stageDialogRef = ref(null);
const pipelineCreateDialogRef = ref(null);

const pipelines = computed(() => pipelinesStore.getPipelines);
const isFetchingPipelines = computed(
  () => pipelinesStore.getUIFlags.fetchingList
);
const isFetchingBoard = computed(
  () =>
    stagesStore.getUIFlags.fetchingList || leadsStore.getUIFlags.fetchingList
);
const isCreatingLead = computed(() => leadsStore.getUIFlags.creatingItem);
const isSavingStage = computed(
  () =>
    stagesStore.getUIFlags.creatingItem || stagesStore.getUIFlags.updatingItem
);
const isDeletingStage = computed(() => stagesStore.getUIFlags.deletingItem);
const isCreatingPipeline = computed(
  () => pipelinesStore.getUIFlags.creatingItem
);
const isDeletingPipeline = computed(
  () => pipelinesStore.getUIFlags.deletingItem
);
const confirmingDeletePipeline = ref(false);

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

const onClickLead = leadId => {
  leadDetailDialogRef.value?.open(leadId);
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

const onAddStage = () => {
  stageDialogRef.value?.open();
};

const onEditStage = stage => {
  stageDialogRef.value?.open(stage);
};

const onSaveStage = async ({ id, name, color }) => {
  try {
    if (id) {
      await stagesStore.update({
        pipelineId: activePipelineId.value,
        id,
        name,
        color,
      });
    } else {
      await stagesStore.create({
        pipelineId: activePipelineId.value,
        name,
        color,
      });
    }
    stageDialogRef.value?.onSuccess();
  } catch {
    useAlert(t('CRM.STAGE.MESSAGES.ERROR'));
  }
};

const onDeleteStage = async id => {
  try {
    await stagesStore.delete({ pipelineId: activePipelineId.value, id });
    stageDialogRef.value?.onSuccess();
  } catch {
    useAlert(t('CRM.STAGE.MESSAGES.DELETE_ERROR'));
  }
};

const onAddPipeline = () => {
  pipelineCreateDialogRef.value?.open();
};

const onCreatePipeline = async ({ name }) => {
  try {
    const pipeline = await pipelinesStore.create({ name });
    pipelineCreateDialogRef.value?.onSuccess();
    onSelectPipeline(pipeline.id);
  } catch {
    useAlert(t('CRM.PIPELINE.CREATE.ERROR'));
  }
};

const onDeletePipeline = async () => {
  if (!confirmingDeletePipeline.value) {
    confirmingDeletePipeline.value = true;
    return;
  }

  const deletedId = activePipelineId.value;
  try {
    await pipelinesStore.delete(deletedId);
    useAlert(t('CRM.PIPELINE.DELETE.SUCCESS'));
    const remainingPipeline = pipelines.value.find(
      pipeline => pipeline.id !== deletedId
    );
    if (remainingPipeline) onSelectPipeline(remainingPipeline.id);
  } catch {
    useAlert(t('CRM.PIPELINE.DELETE.ERROR'));
  } finally {
    confirmingDeletePipeline.value = false;
  }
};

watch(activePipelineId, pipelineId => {
  confirmingDeletePipeline.value = false;
  loadBoard(pipelineId);
});

onMounted(async () => {
  await pipelinesStore.get();
  loadBoard(activePipelineId.value);
});
</script>

<template>
  <div class="flex flex-col h-full w-full min-h-0 min-w-0">
    <div
      class="flex items-center justify-between gap-4 p-4 border-b border-n-weak w-full shrink-0"
    >
      <span class="text-lg font-medium text-n-slate-12">{{
        t('CRM.HEADER')
      }}</span>
      <div class="flex items-center gap-2">
        <PipelineSwitcher
          v-if="pipelines.length > 0"
          :pipelines="pipelines"
          :model-value="activePipelineId"
          @update:model-value="onSelectPipeline"
        />
        <Button
          v-if="activePipelineId"
          icon="i-lucide-trash-2"
          color="ruby"
          variant="ghost"
          size="sm"
          :label="
            confirmingDeletePipeline
              ? t('CRM.PIPELINE.DELETE.CONFIRM')
              : t('CRM.PIPELINE.DELETE.ACTION')
          "
          :is-loading="isDeletingPipeline"
          @click="onDeletePipeline"
        />
        <Button
          icon="i-lucide-plus"
          color="slate"
          variant="ghost"
          size="sm"
          :label="t('CRM.PIPELINE.CREATE.ACTION')"
          @click="onAddPipeline"
        />
      </div>
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
        @click-lead="onClickLead"
        @edit-stage="onEditStage"
        @add-stage="onAddStage"
      />
    </div>
    <LeadCreateDialog
      ref="leadCreateDialogRef"
      :is-loading="isCreatingLead"
      @create="onCreateLead"
    />
    <LeadDetailDialog ref="leadDetailDialogRef" />
    <StageDialog
      ref="stageDialogRef"
      :is-loading="isSavingStage"
      :is-deleting="isDeletingStage"
      @save="onSaveStage"
      @delete="onDeleteStage"
    />
    <PipelineCreateDialog
      ref="pipelineCreateDialogRef"
      :is-loading="isCreatingPipeline"
      @create="onCreatePipeline"
    />
  </div>
</template>
