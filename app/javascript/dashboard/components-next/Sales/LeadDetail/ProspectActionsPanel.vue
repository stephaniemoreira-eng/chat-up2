<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Fase 3 (§18.2, §18.3, §21.2): Assumir/Devolver. Só aparece quando o card está de fato
// vinculado a um lead do Operational Engine -- ver LeadDetailDialog.vue pra a condição exata.
const props = defineProps({
  engineTags: { type: Array, default: () => [] },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['assumir', 'devolver']);

const { t } = useI18n();

const isHuman = computed(() => props.engineTags.includes('humano'));
</script>

<template>
  <div class="flex items-center justify-between gap-3 p-3 border rounded-lg border-n-weak bg-n-alpha-1">
    <span class="text-sm text-n-slate-11">
      {{
        isHuman
          ? t('CRM.LEAD.DETAIL.PROSPECT.CURRENT_MODE_HUMANO')
          : t('CRM.LEAD.DETAIL.PROSPECT.CURRENT_MODE_LAVINIA')
      }}
    </span>
    <Button
      v-if="isHuman"
      size="sm"
      variant="outline"
      color="slate"
      :label="t('CRM.LEAD.DETAIL.PROSPECT.DEVOLVER')"
      :disabled="isSaving"
      @click="emit('devolver')"
    />
    <Button
      v-else
      size="sm"
      variant="outline"
      color="blue"
      :label="t('CRM.LEAD.DETAIL.PROSPECT.ASSUMIR')"
      :disabled="isSaving"
      @click="emit('assumir')"
    />
  </div>
</template>
