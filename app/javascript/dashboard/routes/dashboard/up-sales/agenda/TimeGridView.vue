<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { isSameDay } from './dateHelpers';

const props = defineProps({
  days: { type: Array, required: true }, // 1 Date (day view) or 7 Dates (week view)
  events: { type: Array, required: true },
});
const emit = defineEmits(['select-day']);

const HOUR_START = 6;
const HOUR_END = 22;
const ROW_HEIGHT_PX = 48;
const GRID_HEIGHT_PX = (HOUR_END - HOUR_START) * ROW_HEIGHT_PX;

const hours = Array.from(
  { length: HOUR_END - HOUR_START },
  (_, i) => HOUR_START + i
);

const now = ref(new Date());
let clockTimer = null;
onMounted(() => {
  clockTimer = setInterval(() => {
    now.value = new Date();
  }, 60_000);
});
onUnmounted(() => clearInterval(clockTimer));

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function minutesFromGridStart(date) {
  return (date.getHours() - HOUR_START) * 60 + date.getMinutes();
}

function topPxFor(date) {
  const minutes = clamp(minutesFromGridStart(date), 0, HOUR_END * 60);
  return (minutes / 60) * ROW_HEIGHT_PX;
}

function eventsForDay(day) {
  return props.events.filter(
    event => event.startsAt && !event.isAllDay && isSameDay(event.startsAt, day)
  );
}

function allDayEventsForDay(day) {
  return props.events.filter(
    event => event.isAllDay && isSameDay(event.startsAt, day)
  );
}

function eventStyle(event) {
  const top = topPxFor(event.startsAt);
  const rawEnd = event.endsAt || event.startsAt;
  const bottom = Math.max(topPxFor(rawEnd), top + 20); // 20px floor so a 15min event stays readable
  return {
    top: `${top}px`,
    height: `${clamp(bottom, 0, GRID_HEIGHT_PX) - top}px`,
  };
}

const nowLinePxByDay = computed(() =>
  props.days.map(day =>
    isSameDay(day, now.value) ? topPxFor(now.value) : null
  )
);

function formatEventTime(event) {
  return event.startsAt.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
}

function formatHour(hour) {
  return `${String(hour).padStart(2, '0')}:00`;
}

function openEvent(event) {
  if (event.htmlLink)
    window.open(event.htmlLink, '_blank', 'noopener,noreferrer');
}
</script>

<template>
  <div class="border border-n-weak rounded-lg overflow-hidden">
    <!-- Header: weekday + day number, click jumps to day view (matches MonthView's affordance) -->
    <div class="flex border-b border-n-weak bg-n-solid-1">
      <div class="w-14 flex-shrink-0" />
      <button
        v-for="day in days"
        :key="`h-${day.toISOString()}`"
        type="button"
        class="flex-1 min-w-0 px-2 py-2 text-center hover:bg-n-solid-2"
        @click="emit('select-day', day)"
      >
        <div class="text-xs text-n-slate-11">
          {{ day.toLocaleDateString('pt-BR', { weekday: 'short' }) }}
        </div>
        <div
          class="text-sm font-medium mx-auto mt-0.5 w-7 h-7 flex items-center justify-center rounded-full"
          :class="
            isSameDay(day, now) ? 'bg-n-brand text-white' : 'text-n-slate-12'
          "
        >
          {{ day.getDate() }}
        </div>
      </button>
    </div>

    <!-- All-day events strip -->
    <div
      v-if="days.some(day => allDayEventsForDay(day).length > 0)"
      class="flex border-b border-n-weak"
    >
      <div class="w-14 flex-shrink-0" />
      <div
        v-for="day in days"
        :key="`ad-${day.toISOString()}`"
        class="flex-1 min-w-0 p-1 flex flex-col gap-0.5 border-l border-n-weak first:border-l-0"
      >
        <span
          v-for="event in allDayEventsForDay(day)"
          :key="event.id"
          class="text-xxs truncate rounded px-1 py-0.5 bg-n-solid-2 text-n-slate-12"
          :class="{ 'cursor-pointer hover:bg-n-solid-3': event.htmlLink }"
          @click="openEvent(event)"
        >
          {{ event.summary }}
        </span>
      </div>
    </div>

    <!-- Timed grid -->
    <div class="flex overflow-y-auto max-h-[600px]">
      <div
        class="w-14 flex-shrink-0 relative"
        :style="{ height: `${GRID_HEIGHT_PX}px` }"
      >
        <span
          v-for="hour in hours"
          :key="`label-${hour}`"
          class="absolute right-2 -translate-y-1/2 text-xxs text-n-slate-11"
          :style="{ top: `${(hour - HOUR_START) * ROW_HEIGHT_PX}px` }"
        >
          {{ formatHour(hour) }}
        </span>
      </div>
      <div
        v-for="(day, dayIndex) in days"
        :key="`col-${day.toISOString()}`"
        class="flex-1 min-w-0 relative border-l border-n-weak first:border-l-0"
        :style="{ height: `${GRID_HEIGHT_PX}px` }"
      >
        <div
          v-for="hour in hours"
          :key="`line-${hour}`"
          class="absolute inset-x-0 border-t border-n-weak"
          :style="{ top: `${(hour - HOUR_START) * ROW_HEIGHT_PX}px` }"
        />
        <div
          v-if="nowLinePxByDay[dayIndex] !== null"
          class="absolute inset-x-0 border-t-2 border-n-ruby-9 z-10"
          :style="{ top: `${nowLinePxByDay[dayIndex]}px` }"
        />
        <div
          v-for="event in eventsForDay(day)"
          :key="event.id"
          class="absolute inset-x-0.5 rounded bg-n-brand/15 border-l-2 border-n-brand px-1.5 py-0.5 overflow-hidden cursor-pointer hover:bg-n-brand/25"
          :style="eventStyle(event)"
          @click="openEvent(event)"
        >
          <p class="text-xxs font-medium text-n-slate-12 truncate">
            {{ event.summary }}
          </p>
          <p class="text-xxs text-n-slate-11 truncate">
            {{ formatEventTime(event) }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
