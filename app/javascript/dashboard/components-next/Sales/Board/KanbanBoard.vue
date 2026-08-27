<script setup>
import { useI18n } from 'vue-i18n';
import KanbanColumn from 'dashboard/components-next/Sales/Board/KanbanColumn.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  stages: { type: Array, default: () => [] },
  getLeadsForStage: { type: Function, required: true },
});

const emit = defineEmits([
  'moveLead',
  'clickLead',
  'addLead',
  'editStage',
  'addStage',
]);

const { t } = useI18n();
</script>

<template>
  <div class="flex items-start gap-3 p-4 overflow-x-auto h-full">
    <KanbanColumn
      v-for="stage in stages"
      :key="stage.id"
      :stage="stage"
      :leads="getLeadsForStage(stage.id)"
      @move-lead="payload => emit('moveLead', payload)"
      @click-lead="id => emit('clickLead', id)"
      @add-lead="stageId => emit('addLead', stageId)"
      @edit-stage="stage_ => emit('editStage', stage_)"
    />
    <Button
      icon="i-lucide-plus"
      color="slate"
      variant="faded"
      size="sm"
      :label="t('CRM.STAGE.CREATE.ACTION')"
      class="flex-shrink-0"
      @click="emit('addStage')"
    />
  </div>
</template>
