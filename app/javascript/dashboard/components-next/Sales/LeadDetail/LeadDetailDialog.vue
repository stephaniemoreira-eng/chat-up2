<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useSalesLeadsStore } from 'dashboard/stores/sales/leads';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SummaryPanel from 'dashboard/components-next/Sales/LeadDetail/SummaryPanel.vue';
import ScanPanel from 'dashboard/components-next/Sales/LeadDetail/ScanPanel.vue';
import Timeline from 'dashboard/components-next/Sales/LeadDetail/Timeline.vue';

const { t } = useI18n();
const leadsStore = useSalesLeadsStore();

const dialogRef = ref(null);
const leadId = ref(null);
const entries = ref([]);
const nextBefore = ref(null);
const isLoadingTimeline = ref(false);
const isSavingSummary = ref(false);

const lead = computed(() =>
  leadId.value ? leadsStore.getRecord(leadId.value) : null
);

const hasMore = computed(() => Boolean(nextBefore.value));

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
      <Timeline
        :entries="entries"
        :is-loading="isLoadingTimeline"
        :has-more="hasMore"
        @load-more="loadTimeline({ append: true })"
      />
    </div>
  </Dialog>
</template>
