<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { addDays, isSameDay, startOfMonth, startOfWeek } from './dateHelpers';

const props = defineProps({
  referenceDate: { type: Date, required: true },
  events: { type: Array, required: true },
});

const emit = defineEmits(['select-day']);

const { t } = useI18n();

const WEEKDAY_LABELS = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const MAX_VISIBLE_PER_DAY = 3;
const today = new Date();

const weeks = computed(() => {
  const monthStart = startOfMonth(props.referenceDate);
  const monthEnd = new Date(
    props.referenceDate.getFullYear(),
    props.referenceDate.getMonth() + 1,
    0
  );
  const gridStart = startOfWeek(monthStart);
  const gridEnd = addDays(startOfWeek(monthEnd), 7);

  const days = [];
  for (let d = new Date(gridStart); d < gridEnd; d = addDays(d, 1)) {
    days.push(new Date(d));
  }
  const out = [];
  for (let i = 0; i < days.length; i += 7) {
    out.push(days.slice(i, i + 7));
  }
  return out;
});

const eventsByDay = computed(() => {
  const map = new Map();
  props.events
    .filter(event => event.startsAt)
    .sort((a, b) => a.startsAt - b.startsAt)
    .forEach(event => {
      const key = event.startsAt.toDateString();
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(event);
    });
  return map;
});

function eventsForDay(day) {
  return eventsByDay.value.get(day.toDateString()) || [];
}

function isCurrentMonth(day) {
  return day.getMonth() === props.referenceDate.getMonth();
}

function formatEventTime(event) {
  return event.startsAt.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function openEvent(event) {
  if (event.htmlLink)
    window.open(event.htmlLink, '_blank', 'noopener,noreferrer');
}
</script>

<template>
  <div class="border border-n-weak rounded-lg overflow-hidden">
    <div class="grid grid-cols-7 border-b border-n-weak bg-n-solid-1">
      <div
        v-for="label in WEEKDAY_LABELS"
        :key="label"
        class="px-2 py-2 text-xs font-medium text-n-slate-11 text-center"
      >
        {{ label }}
      </div>
    </div>
    <div class="grid grid-cols-7">
      <template v-for="(week, wi) in weeks" :key="wi">
        <button
          v-for="day in week"
          :key="day.toISOString()"
          type="button"
          class="min-h-24 border-b border-r border-n-weak p-1.5 flex flex-col gap-1 items-stretch text-left hover:bg-n-solid-1 last:border-r-0"
          @click="emit('select-day', day)"
        >
          <span
            class="text-xs w-6 h-6 flex items-center justify-center rounded-full flex-shrink-0"
            :class="[
              !isCurrentMonth(day) ? 'text-n-slate-9' : 'text-n-slate-12',
              isSameDay(day, today) ? 'bg-n-brand text-white' : '',
            ]"
          >
            {{ day.getDate() }}
          </span>
          <div class="flex flex-col gap-0.5 overflow-hidden min-w-0">
            <span
              v-for="event in eventsForDay(day).slice(0, MAX_VISIBLE_PER_DAY)"
              :key="event.id"
              class="text-xxs truncate rounded px-1 py-0.5 bg-n-solid-2 text-n-slate-12"
              :class="{ 'hover:bg-n-solid-3': event.htmlLink }"
              @click.stop="openEvent(event)"
            >
              {{ formatEventTime(event) }} {{ event.summary }}
            </span>
            <span
              v-if="eventsForDay(day).length > MAX_VISIBLE_PER_DAY"
              class="text-xxs text-n-slate-11 px-1"
            >
              {{
                t('UP_SALES.AGENDA.MORE_COUNT', {
                  n: eventsForDay(day).length - MAX_VISIBLE_PER_DAY,
                })
              }}
            </span>
          </div>
        </button>
      </template>
    </div>
  </div>
</template>
