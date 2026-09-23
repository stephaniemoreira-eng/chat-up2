<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';

// Fase 9 (§21.2, §20.2, §20.3): ações humanas mínimas do Kanban Comercial. Só aparece quando o
// card está de fato vinculado a um lead do Operational Engine (§5.7 -- toda ação de negócio
// passa pelo Engine, nunca escrita direta) -- ver CommercialActionsPanel.spec.js e
// LeadDetailDialog.vue pra a condição exata.
//
// CP-05 (P1-025-02, P1-023-03, P2-025-03): a visibilidade aqui só espelha as guardas do Engine
// (OperationalEngine::ComercialActionGuard), que valem mesmo para chamada direta. Máquina do §8.4:
// Oportunidade → Em acompanhamento → Ganho/Perdido -- Ganho/Perdido só em Em acompanhamento; a
// movimentação Oportunidade → Em acompanhamento é uma ação do Engine (botão ou drag convertido).
// NO-SHOW pode ser removido manualmente (§20.3); o evento histórico permanece.
const props = defineProps({
  engineTags: { type: Array, default: () => [] },
  engineStageKey: { type: String, default: null },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits([
  'register-callback-realizado',
  'register-no-show',
  'setPropensao',
  'registerResultado',
  'advance-etapa-comercial',
  'remove-no-show',
]);

const { t } = useI18n();

const PROPENSOES = ['frio', 'morno', 'quente'];

const isResolved = computed(() =>
  ['ganho', 'perdido'].includes(props.engineStageKey)
);
const hasPendingCallback = computed(() =>
  props.engineTags.includes('callback')
);
const hasNoShow = computed(() => props.engineTags.includes('no_show'));
const canResolve = computed(() => props.engineStageKey === 'em_acompanhamento');
const canStartAcompanhamento = computed(
  () => props.engineStageKey === 'oportunidade'
);
const currentPropensao = computed(
  () => PROPENSOES.find(p => props.engineTags.includes(p)) || null
);

const motivoPerda = ref('');

const onSetPropensao = propensao => emit('setPropensao', propensao);
const onRegisterResultado = resultado => {
  emit('registerResultado', {
    resultado,
    motivoPerda: resultado === 'perdido' ? motivoPerda.value || null : null,
  });
  motivoPerda.value = '';
};
</script>

<template>
  <div
    class="flex flex-col gap-4 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
  >
    <span class="text-sm font-medium text-n-slate-11">
      {{ t('CRM.LEAD.DETAIL.COMMERCIAL.TITLE') }}
    </span>

    <div v-if="isResolved" class="text-sm text-n-slate-11">
      {{
        engineStageKey === 'ganho'
          ? t('CRM.LEAD.DETAIL.COMMERCIAL.RESOLVED_WON')
          : t('CRM.LEAD.DETAIL.COMMERCIAL.RESOLVED_LOST')
      }}
    </div>

    <template v-else>
      <div class="flex flex-col gap-1">
        <span class="text-xs text-n-slate-10">
          {{ t('CRM.LEAD.DETAIL.COMMERCIAL.PROPENSAO.LABEL') }}
        </span>
        <div class="flex gap-2">
          <Button
            v-for="propensao in PROPENSOES"
            :key="propensao"
            size="sm"
            :variant="currentPropensao === propensao ? 'solid' : 'outline'"
            :color="currentPropensao === propensao ? 'blue' : 'slate'"
            :label="
              t(
                `CRM.LEAD.DETAIL.COMMERCIAL.PROPENSAO.${propensao.toUpperCase()}`
              )
            "
            :disabled="isSaving"
            @click="onSetPropensao(propensao)"
          />
        </div>
      </div>

      <div class="flex flex-wrap gap-2">
        <Button
          v-if="hasPendingCallback"
          size="sm"
          variant="outline"
          color="blue"
          :label="t('CRM.LEAD.DETAIL.COMMERCIAL.CALLBACK_REALIZADO')"
          :disabled="isSaving"
          @click="emit('register-callback-realizado')"
        />
        <Button
          size="sm"
          variant="outline"
          color="slate"
          :label="t('CRM.LEAD.DETAIL.COMMERCIAL.NO_SHOW')"
          :disabled="isSaving"
          @click="emit('register-no-show')"
        />
        <Button
          v-if="hasNoShow"
          size="sm"
          variant="outline"
          color="slate"
          :label="t('CRM.LEAD.DETAIL.COMMERCIAL.REMOVE_NO_SHOW')"
          :disabled="isSaving"
          @click="emit('remove-no-show')"
        />
        <Button
          v-if="canStartAcompanhamento"
          size="sm"
          variant="outline"
          color="blue"
          :label="t('CRM.LEAD.DETAIL.COMMERCIAL.START_ACOMPANHAMENTO')"
          :disabled="isSaving"
          @click="emit('advance-etapa-comercial', 'em_acompanhamento')"
        />
      </div>

      <div
        v-if="!canResolve"
        class="pt-2 text-xs border-t border-n-weak text-n-slate-10"
      >
        {{ t('CRM.LEAD.DETAIL.COMMERCIAL.RESULT_REQUIRES_ACOMPANHAMENTO') }}
      </div>

      <div v-else class="flex flex-col gap-2 pt-2 border-t border-n-weak">
        <textarea
          v-model="motivoPerda"
          rows="2"
          class="w-full p-2 text-sm border rounded-lg resize-none bg-n-alpha-1 border-n-weak text-n-slate-12 focus:outline-none focus:border-n-brand"
          :placeholder="
            t('CRM.LEAD.DETAIL.COMMERCIAL.MOTIVO_PERDA_PLACEHOLDER')
          "
          :disabled="isSaving"
        />
        <div class="flex justify-end gap-2">
          <Button
            size="sm"
            variant="outline"
            color="ruby"
            :label="t('CRM.LEAD.DETAIL.COMMERCIAL.MARK_LOST')"
            :disabled="isSaving"
            @click="onRegisterResultado('perdido')"
          />
          <Button
            size="sm"
            color="teal"
            :label="t('CRM.LEAD.DETAIL.COMMERCIAL.MARK_WON')"
            :disabled="isSaving"
            @click="onRegisterResultado('ganho')"
          />
        </div>
      </div>
    </template>
  </div>
</template>
