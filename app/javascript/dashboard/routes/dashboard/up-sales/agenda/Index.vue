<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import CalendarEventsAPI from 'dashboard/api/upSales/calendarEvents';

const { t } = useI18n();

const isLoading = ref(true);
const errorMessage = ref('');
const events = ref([]);

const SOON_THRESHOLD_MS = 2 * 60 * 60 * 1000; // 2h — matches an operator's "starting soon" instinct

const now = ref(new Date());

const eventsWithMeta = computed(() =>
  events.value.map(event => {
    const startsAt = event.start ? new Date(event.start) : null;
    const msUntilStart = startsAt
      ? startsAt.getTime() - now.value.getTime()
      : null;
    return {
      ...event,
      startsAt,
      isSoon:
        msUntilStart !== null &&
        msUntilStart >= 0 &&
        msUntilStart <= SOON_THRESHOLD_MS,
      isPast: msUntilStart !== null && msUntilStart < 0,
    };
  })
);

const upcomingEvents = computed(() =>
  eventsWithMeta.value.filter(event => !event.isPast)
);

const formatDateTime = date => {
  if (!date) return '';
  return date.toLocaleString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const fetchEvents = async () => {
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await CalendarEventsAPI.list();
    events.value = data.payload || [];
  } catch (error) {
    errorMessage.value =
      error.response?.data?.error || t('UP_SALES.AGENDA.ERROR');
  } finally {
    isLoading.value = false;
  }
};

onMounted(() => {
  now.value = new Date();
  fetchEvents();
});
</script>

<template>
  <div class="p-6 max-w-3xl">
    <h1 class="text-xl font-semibold text-n-slate-12 mb-6">
      {{ t('UP_SALES.AGENDA.TITLE') }}
    </h1>

    <div v-if="isLoading" class="text-sm text-n-slate-11">
      {{ t('UP_SALES.AGENDA.LOADING') }}
    </div>

    <div
      v-else-if="errorMessage"
      class="rounded-lg border border-n-weak bg-n-solid-1 p-5 text-sm text-n-slate-11"
    >
      {{ errorMessage }}
    </div>

    <div
      v-else-if="upcomingEvents.length === 0"
      class="text-sm text-n-slate-11"
    >
      {{ t('UP_SALES.AGENDA.EMPTY') }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <div
        v-for="event in upcomingEvents"
        :key="event.id"
        class="flex items-start gap-3 rounded-lg border p-4"
        :class="
          event.isSoon
            ? 'border-n-brand bg-n-brand/5'
            : 'border-n-weak bg-n-solid-1'
        "
      >
        <div class="flex flex-col min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <span class="text-sm font-medium text-n-slate-12">
              {{ event.summary || t('UP_SALES.AGENDA.NO_TITLE') }}
            </span>
            <span
              v-if="event.isSoon"
              class="text-xxs font-medium text-n-brand bg-n-brand/10 rounded-full px-2 py-0.5 flex-shrink-0"
            >
              {{ t('UP_SALES.AGENDA.STARTING_SOON') }}
            </span>
          </div>
          <span class="text-xs text-n-slate-11 mt-1">
            {{ formatDateTime(event.startsAt) }}
          </span>
        </div>
        <div class="flex items-center gap-3 flex-shrink-0">
          <a
            v-if="event.meetLink"
            :href="event.meetLink"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs text-n-brand hover:underline"
          >
            {{ t('UP_SALES.AGENDA.JOIN_MEET') }}
          </a>
          <a
            v-if="event.htmlLink"
            :href="event.htmlLink"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs text-n-slate-11 hover:underline"
          >
            {{ t('UP_SALES.AGENDA.OPEN_IN_CALENDAR') }}
          </a>
        </div>
      </div>
    </div>
  </div>
</template>
