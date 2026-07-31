<script setup>
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

defineProps({
  entries: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
});

defineEmits(['load-more']);

const { t } = useI18n();

const stageTransitionLabel = entry =>
  entry.from_stage_name
    ? t('CRM.LEAD.DETAIL.TIMELINE.STAGE_TRANSITION', {
        from: entry.from_stage_name,
        to: entry.to_stage_name,
      })
    : t('CRM.LEAD.DETAIL.TIMELINE.STAGE_TRANSITION_FIRST', {
        to: entry.to_stage_name,
      });
</script>

<template>
  <div class="flex flex-col gap-3">
    <span class="text-sm font-medium text-n-slate-11">
      {{ t('CRM.LEAD.DETAIL.TIMELINE.TITLE') }}
    </span>

    <p v-if="!entries.length && !isLoading" class="text-sm text-n-slate-10">
      {{ t('CRM.LEAD.DETAIL.TIMELINE.EMPTY') }}
    </p>

    <div
      v-for="entry in entries"
      :key="`${entry.type}-${entry.id}`"
      class="flex items-start gap-2"
    >
      <Avatar
        :name="entry.sender_name || entry.user_name || '?'"
        :size="20"
        rounded-full
      />
      <div class="flex flex-col min-w-0 gap-0.5">
        <template v-if="entry.type === 'message'">
          <span class="text-sm text-n-slate-12 whitespace-pre-line">{{
            entry.content
          }}</span>
        </template>
        <template v-else-if="entry.type === 'note'">
          <span class="text-sm text-n-slate-12 whitespace-pre-line">{{
            entry.content
          }}</span>
        </template>
        <template v-else-if="entry.type === 'stage_transition'">
          <span class="text-sm text-n-slate-11">{{
            stageTransitionLabel(entry)
          }}</span>
        </template>
        <template v-else-if="entry.type === 'activity'">
          <span class="text-sm text-n-slate-11">
            {{ t('CRM.LEAD.DETAIL.TIMELINE.SUMMARY_UPDATED') }}
          </span>
        </template>
        <span class="text-xs text-n-slate-10">
          {{ dynamicTime(entry.created_at) }}
        </span>
      </div>
    </div>

    <Button
      v-if="hasMore"
      :label="t('CRM.LEAD.DETAIL.TIMELINE.LOAD_MORE')"
      variant="faded"
      color="slate"
      size="sm"
      :is-loading="isLoading"
      @click="$emit('load-more')"
    />
  </div>
</template>
