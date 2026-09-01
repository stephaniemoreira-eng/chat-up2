<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/sales/leads';
import CalendarEventsAPI from 'dashboard/api/upSales/calendarEvents';

const { t } = useI18n();

const isLoading = ref(true);
const leadsCount = ref(0);
const dealsWonCount = ref(0);
const lastSearchAt = ref(null);
const meetingsScheduledCount = ref(null);

const formatDate = iso => {
  if (!iso) return t('UP_SALES.DASHBOARD.LAST_SEARCH_EMPTY');
  return new Date(iso).toLocaleDateString('pt-BR');
};

const fetchMeetingsScheduledThisMonth = async () => {
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  try {
    const { data } = await CalendarEventsAPI.list({
      timeMin: monthStart.toISOString(),
      timeMax: monthEnd.toISOString(),
      maxResults: 50,
    });
    meetingsScheduledCount.value = (data.payload || []).length;
  } catch {
    // No calendar connected yet, or up2-agents unreachable — leave the placeholder dash instead
    // of a scary error on a dashboard tile.
    meetingsScheduledCount.value = null;
  }
};

onMounted(async () => {
  try {
    const { data } = await LeadsAPI.summary();
    leadsCount.value = data.leads_count;
    dealsWonCount.value = data.deals_won_count;
    lastSearchAt.value = data.last_search_at;
  } finally {
    isLoading.value = false;
  }
  fetchMeetingsScheduledThisMonth();
});
</script>

<template>
  <div class="p-6">
    <h1 class="text-xl font-semibold text-n-slate-12 mb-6">
      {{ t('UP_SALES.DASHBOARD.TITLE') }}
    </h1>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
        <p class="text-sm text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.LEADS_COUNT') }}
        </p>
        <p class="text-2xl font-semibold text-n-slate-12 mt-2">
          {{ isLoading ? '…' : leadsCount }}
        </p>
      </div>
      <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
        <p class="text-sm text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.LAST_SEARCH') }}
        </p>
        <p class="text-2xl font-semibold text-n-slate-12 mt-2">
          {{ isLoading ? '…' : formatDate(lastSearchAt) }}
        </p>
      </div>
      <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
        <p class="text-sm text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.MEETINGS_SCHEDULED') }}
        </p>
        <p class="text-2xl font-semibold text-n-slate-12 mt-2">
          {{
            meetingsScheduledCount === null
              ? t('UP_SALES.DASHBOARD.MEETINGS_PLACEHOLDER')
              : meetingsScheduledCount
          }}
        </p>
      </div>
      <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
        <p class="text-sm text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.DEALS_WON') }}
        </p>
        <p class="text-2xl font-semibold text-n-slate-12 mt-2">
          {{ isLoading ? '…' : dealsWonCount }}
        </p>
      </div>
    </div>
  </div>
</template>
