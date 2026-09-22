<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useSalesLeadsStore } from 'dashboard/stores/sales/leads';
import { useSalesStagesStore } from 'dashboard/stores/sales/stages';
import { useSalesPipelinesStore } from 'dashboard/stores/sales/pipelines';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SummaryPanel from 'dashboard/components-next/Sales/LeadDetail/SummaryPanel.vue';
import ScanPanel from 'dashboard/components-next/Sales/LeadDetail/ScanPanel.vue';
import CommercialActionsPanel from 'dashboard/components-next/Sales/LeadDetail/CommercialActionsPanel.vue';
import Timeline from 'dashboard/components-next/Sales/LeadDetail/Timeline.vue';

const { t } = useI18n();
const leadsStore = useSalesLeadsStore();
const stagesStore = useSalesStagesStore();
const pipelinesStore = useSalesPipelinesStore();

const dialogRef = ref(null);
const leadId = ref(null);
const entries = ref([]);
const nextBefore = ref(null);
const isLoadingTimeline = ref(false);
const isSavingSummary = ref(false);
const isSavingCommercialAction = ref(false);

const lead = computed(() =>
  leadId.value ? leadsStore.getRecord(leadId.value) : null
);

const hasMore = computed(() => Boolean(nextBefore.value));

// Fase 9 (§21.2): as ações comerciais só fazem sentido num card do pipeline "Oportunidades"
// (engine_kind comercial) de verdade vinculado a um lead do Engine -- um card manual criado à
// mão nesse mesmo pipeline (sem passar pelo ComercialProjectionSync) não tem operational_lead_id
// e não deve mostrar o painel.
const isCommercialLead = computed(() => {
  if (!lead.value?.operational_lead_id) return false;
  const stage = stagesStore.getRecord(lead.value.sales_stage_id);
  const pipeline = stage && pipelinesStore.getRecord(stage.sales_pipeline_id);
  return pipeline?.engine_kind === 'comercial';
});

const engineTags = computed(() => lead.value?.custom_attributes?.engine_tags || []);
const engineStageKey = computed(
  () => stagesStore.getRecord(lead.value?.sales_stage_id)?.engine_stage_key || null
);

const loadTimeline = async ({ append = false } = {}) => {
  isLoadingTimeline.value = true;
  try {
    const payload = await leadsStore.fetchTimeline({
      id: leadId.value,
      before: append ? nextBefore.value : undefined,
    });
    entries.value = append
      ? [...entries.value, ...payload.entries]
      : payload.entries;
    nextBefore.value = payload.next_before;
  } catch {
    useAlert(t('CRM.LEAD.DETAIL.TIMELINE.ERROR'));
  } finally {
    isLoadingTimeline.value = false;
  }
};

const open = async id => {
  leadId.value = id;
  entries.value = [];
  nextBefore.value = null;
  dialogRef.value?.open();
  await loadTimeline();
};

const onSaveSummary = async summary => {
  isSavingSummary.value = true;
  try {
    await leadsStore.updateSummary({ id: leadId.value, summary });
    useAlert(t('CRM.LEAD.DETAIL.SUMMARY.SUCCESS'));
    await loadTimeline();
  } catch {
    useAlert(t('CRM.LEAD.DETAIL.SUMMARY.ERROR'));
  } finally {
    isSavingSummary.value = false;
  }
};

const runCommercialAction = async (action, errorKey) => {
  isSavingCommercialAction.value = true;
  try {
    await action();
    await loadTimeline();
  } catch {
    useAlert(t(errorKey));
  } finally {
    isSavingCommercialAction.value = false;
  }
};

const onRegisterCallbackRealizado = () =>
  runCommercialAction(
    () => leadsStore.registerCallbackRealizado({ id: leadId.value }),
    'CRM.LEAD.DETAIL.COMMERCIAL.MESSAGES.ERROR'
  );

const onRegisterNoShow = () =>
  runCommercialAction(
    () => leadsStore.registerNoShow({ id: leadId.value }),
    'CRM.LEAD.DETAIL.COMMERCIAL.MESSAGES.ERROR'
  );

const onSetPropensao = propensaoFechamento =>
  runCommercialAction(
    () =>
      leadsStore.setPropensao({ id: leadId.value, propensaoFechamento }),
    'CRM.LEAD.DETAIL.COMMERCIAL.MESSAGES.ERROR'
  );

const onRegisterResultado = ({ resultado, motivoPerda }) =>
  runCommercialAction(
    () =>
      leadsStore.registerResultadoComercial({
        id: leadId.value,
        resultadoComercial: resultado,
        motivoPerda,
      }),
    'CRM.LEAD.DETAIL.COMMERCIAL.MESSAGES.ERROR'
  );

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="lead?.title"
    :description="lead?.contact_name"
    width="xl"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <div v-if="lead" class="flex flex-col gap-6">
      <ScanPanel
        v-if="lead.scan_status"
        :scan-status="lead.scan_status"
        :scan-score="lead.scan_score"
        :scan-faixa="lead.scan_faixa"
        :scan-pilares="lead.scan_pilares"
        :scan-evidencias="lead.scan_evidencias"
      />
      <SummaryPanel
        :summary="lead.summary"
        :is-saving="isSavingSummary"
        @save="onSaveSummary"
      />
      <CommercialActionsPanel
        v-if="isCommercialLead"
        :engine-tags="engineTags"
        :engine-stage-key="engineStageKey"
        :is-saving="isSavingCommercialAction"
        @register-callback-realizado="onRegisterCallbackRealizado"
        @register-no-show="onRegisterNoShow"
        @set-propensao="onSetPropensao"
        @register-resultado="onRegisterResultado"
      />
      <Timeline
        :entries="entries"
        :is-loading="isLoadingTimeline"
        :has-more="hasMore"
        @load-more="loadTimeline({ append: true })"
      />
    </div>
  </Dialog>
</template>
