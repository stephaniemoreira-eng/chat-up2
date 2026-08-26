<script setup>
import { computed } from 'vue';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import LeadCard from 'dashboard/components-next/Sales/Board/LeadCard.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
});

const emit = defineEmits(['moveLead', 'clickLead', 'addLead']);

const localLeads = computed({
  get: () => props.leads,
  set: () => {}, // list mutations are reconciled by the parent store; onDragEnd persists the move
});

const onDragEnd = event => {
  const leadId = Number(event.item.dataset.leadId);
  const toStageId = Number(event.to.dataset.stageId);
  if (!leadId || !toStageId) return;

  emit('moveLead', { id: leadId, salesStageId: toStageId });
};
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 w-72 gap-3 p-3 rounded-lg bg-n-alpha-1"
  >
    <div class="flex items-center justify-between gap-2 px-1">
      <div class="flex items-center gap-2 min-w-0">
        <span
          v-if="stage.color"
          class="size-2.5 rounded-full shrink-0"
          :style="{ backgroundColor: stage.color }"
        />
        <span class="text-sm font-medium text-n-slate-12 truncate">
          {{ stage.name }}
        </span>
        <span
          class="text-[11px] font-medium text-n-slate-11 bg-n-slate-3 rounded-full px-1.5 py-0.5 shrink-0"
        >
          {{ leads.length }}
        </span>
      </div>
      <Button
        icon="i-lucide-plus"
        color="slate"
        variant="ghost"
        size="sm"
        @click="emit('addLead', stage.id)"
      />
    </div>
    <Draggable
      :list="localLeads"
      group="sales-leads"
      item-key="id"
      ghost-class="opacity-30"
      class="flex flex-col gap-2 min-h-[2rem]"
      :data-stage-id="stage.id"
      @end="onDragEnd"
    >
      <template #item="{ element: lead }">
        <LeadCard
          :id="lead.id"
          :title="lead.title"
          :value="lead.value"
          :contact-name="lead.contact_name"
          :assignee-name="lead.assignee_name"
          @click="emit('clickLead', lead.id)"
        />
      </template>
    </Draggable>
  </div>
</template>
