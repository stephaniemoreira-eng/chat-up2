<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarEventsAPI from 'dashboard/api/upSales/calendarEvents';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MonthView from './MonthView.vue';
import TimeGridView from './TimeGridView.vue';
import {
  addDays,
  addMonths,
  isAllDayValue,
  parseEventDate,
  startOfDay,
  startOfMonth,
  startOfWeek,
} from './dateHelpers';

const { t } = useI18n();

const VIEW_OPTIONS = [
  { value: 'month', label: t('UP_SALES.AGENDA.VIEW_MONTH') },
  { value: 'week', label: t('UP_SALES.AGENDA.VIEW_WEEK') },
  { value: 'day', label: t('UP_SALES.AGENDA.VIEW_DAY') },
];

const viewMode = ref('month');
const referenceDate = ref(new Date());
const events = ref([]);
const isLoading = ref(true);
const errorMessage = ref('');

const range = computed(() => {
  if (viewMode.value === 'day') {
    const start = startOfDay(referenceDate.value);
    return { start, end: addDays(start, 1) };
  }
  if (viewMode.value === 'week') {
    const start = startOfWeek(referenceDate.value);
    return { start, end: addDays(start, 7) };
  }
  const monthStart = startOfMonth(referenceDate.value);
  const monthEnd = new Date(
    referenceDate.value.getFullYear(),
    referenceDate.value.getMonth() + 1,
    0
  );
  const start = startOfWeek(monthStart);
  const end = addDays(startOfWeek(monthEnd), 7);
  return { start, end };
});

const weekOrDayColumns = computed(() =>
  viewMode.value === 'day'
    ? [startOfDay(referenceDate.value)]
    : Array.from({ length: 7 }, (_, i) => addDays(range.value.start, i))
);

const title = computed(() => {
  if (viewMode.value === 'day') {
    return referenceDate.value.toLocaleDateString('pt-BR', {
      day: 'numeric',
      month: 'long',
      year: 'numeric',
    });
  }
  if (viewMode.value === 'week') {
    const start = range.value.start;
    const last = addDays(range.value.end, -1);
    const sameMonth = start.getMonth() === last.getMonth();
    return sameMonth
      ? `${start.getDate()}–${last.getDate()} de ${start.toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })}`
      : `${start.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short' })} – ${last.toLocaleDateString('pt-BR', { day: 'numeric', month: 'short', year: 'numeric' })}`;
  }
  return referenceDate.value.toLocaleDateString('pt-BR', {
    month: 'long',
    year: 'numeric',
  });
});

// Bumped on every call so a slower, now-stale request can't overwrite a fresher one that
// happened to resolve first (e.g. clicking Prev/Next twice quickly, or Month -> Week -> Month).
let fetchToken = 0;

const fetchEvents = async () => {
  fetchToken += 1;
  const thisFetch = fetchToken;
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await CalendarEventsAPI.list({
      timeMin: range.value.start.toISOString(),
      timeMax: range.value.end.toISOString(),
      maxResults: 50,
    });
    if (thisFetch !== fetchToken) return;
    events.value = (data.payload || [])
      .filter(event => event.start)
      .map(event => {
        const isAllDay = isAllDayValue(event.start);
        return {
          ...event,
          isAllDay,
          startsAt: parseEventDate(event.start, isAllDay),
          endsAt: event.end ? parseEventDate(event.end, isAllDay) : null,
        };
      });
  } catch (error) {
    if (thisFetch !== fetchToken) return;
    errorMessage.value =
      error.response?.data?.error || t('UP_SALES.AGENDA.ERROR');
    events.value = [];
  } finally {
    if (thisFetch === fetchToken) isLoading.value = false;
  }
};

function goToday() {
  referenceDate.value = new Date();
}
function goPrev() {
  if (viewMode.value === 'day')
    referenceDate.value = addDays(referenceDate.value, -1);
  else if (viewMode.value === 'week')
    referenceDate.value = addDays(referenceDate.value, -7);
  else referenceDate.value = addMonths(referenceDate.value, -1);
}
function goNext() {
  if (viewMode.value === 'day')
    referenceDate.value = addDays(referenceDate.value, 1);
  else if (viewMode.value === 'week')
    referenceDate.value = addDays(referenceDate.value, 7);
  else referenceDate.value = addMonths(referenceDate.value, 1);
}
function selectDay(day) {
  referenceDate.value = day;
  viewMode.value = 'day';
}

watch(() => range.value, fetchEvents);
onMounted(fetchEvents);
</script>

<template>
  <div class="p-6">
    <div class="flex items-center flex-wrap gap-3 mb-4">
      <h1 class="text-xl font-semibold text-n-slate-12 mr-2">
        {{ t('UP_SALES.AGENDA.TITLE') }}
      </h1>
      <Button
        :label="t('UP_SALES.AGENDA.TODAY')"
        variant="faded"
        size="sm"
        @click="goToday"
      />
      <div class="flex items-center gap-1">
        <Button
          icon="i-lucide-chevron-left"
          variant="ghost"
          size="sm"
          @click="goPrev"
        />
        <Button
          icon="i-lucide-chevron-right"
          variant="ghost"
          size="sm"
          @click="goNext"
        />
      </div>
      <span class="text-sm font-medium text-n-slate-12 capitalize">{{
        title
      }}</span>
      <ComboBox
        :model-value="viewMode"
        :options="VIEW_OPTIONS"
        class="w-32 ml-auto"
        @update:model-value="value => (viewMode = value)"
      />
    </div>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('UP_SALES.AGENDA.LOADING') }}
    </div>
    <div
      v-else-if="errorMessage"
      class="rounded-lg border border-n-weak bg-n-solid-1 p-5 text-sm text-n-slate-11"
    >
      {{ errorMessage }}
    </div>
    <MonthView
      v-else-if="viewMode === 'month'"
      :reference-date="referenceDate"
      :events="events"
      @select-day="selectDay"
    />
    <TimeGridView
      v-else
      :days="weekOrDayColumns"
      :events="events"
      @select-day="selectDay"
    />
  </div>
</template>
