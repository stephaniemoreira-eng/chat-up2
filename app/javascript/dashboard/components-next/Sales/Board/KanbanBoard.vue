<script setup>
import KanbanColumn from 'dashboard/components-next/Sales/Board/KanbanColumn.vue';

defineProps({
  stages: { type: Array, default: () => [] },
  getLeadsForStage: { type: Function, required: true },
});

const emit = defineEmits(['moveLead', 'clickLead', 'addLead']);
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
    />
  </div>
</template>
