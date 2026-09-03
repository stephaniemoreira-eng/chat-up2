<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  id: { type: Number, required: true },
  title: { type: String, required: true },
  value: { type: [String, Number], default: null },
  contactName: { type: String, default: '' },
  assigneeName: { type: String, default: '' },
  stageColor: { type: String, default: '' },
  scanScore: { type: Number, default: null },
  scanFaixa: { type: String, default: '' },
});

defineEmits(['click']);

const { t } = useI18n();

const displayContactName = computed(
  () => props.contactName || t('CRM.LEAD.UNNAMED_CONTACT')
);

const formattedValue = computed(() => {
  if (props.value === null || props.value === '') return '';
  return Number(props.value).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
});

// Cores do SCAN v1 (ver ScanWeights::FAIXAS no backend -- manter as 3 faixas em sincronia).
const SCAN_FAIXA_CLASSES = {
  baixa_prioridade: 'bg-n-slate-3 text-n-slate-11',
  revisao_humana: 'bg-n-amber-3 text-n-amber-11',
  revisao_prioritaria: 'bg-n-teal-3 text-n-teal-11',
};

const scanBadgeClass = computed(
  () => SCAN_FAIXA_CLASSES[props.scanFaixa] || 'bg-n-slate-3 text-n-slate-11'
);

const showScanBadge = computed(
  () => props.scanScore !== null && props.scanScore !== undefined
);
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 rounded-lg cursor-grab bg-n-solid-1 border border-n-weak border-l-2 hover:border-n-slate-6 transition-colors active:cursor-grabbing"
    :style="{ borderLeftColor: stageColor || 'transparent' }"
    :data-lead-id="id"
    @click="$emit('click', id)"
  >
    <div class="flex items-start justify-between gap-2">
      <span class="text-sm font-medium text-n-slate-12 line-clamp-2">
        {{ title }}
      </span>
      <span
        v-if="showScanBadge"
        class="text-[11px] font-medium rounded-full px-1.5 py-0.5 shrink-0"
        :class="scanBadgeClass"
      >
        {{ scanScore }}
      </span>
    </div>
    <div class="flex items-center justify-between gap-2 min-w-0">
      <div class="flex items-center gap-1.5 min-w-0">
        <Avatar :name="displayContactName" :size="16" rounded-full />
        <span class="text-xs text-n-slate-11 truncate">
          {{ displayContactName }}
        </span>
      </div>
      <span
        v-if="formattedValue"
        class="text-xs font-medium text-n-slate-11 shrink-0"
      >
        {{ formattedValue }}
      </span>
    </div>
    <div v-if="assigneeName" class="flex items-center gap-1.5">
      <Avatar :name="assigneeName" :size="16" rounded-full />
      <span class="text-xs text-n-slate-11 truncate">{{ assigneeName }}</span>
    </div>
  </div>
</template>
