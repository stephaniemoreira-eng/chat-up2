<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  scanFaixaClass,
  SCAN_PILAR_BAR_CLASS,
  SCAN_PILAR_BAR_ATTENTION_CLASS,
  SCAN_PILAR_TRACK_CLASS,
  SCAN_PILAR_TRACK_ATTENTION_CLASS,
  SCAN_PILAR_VALUE_CLASS,
  SCAN_PILAR_VALUE_ATTENTION_CLASS,
} from 'dashboard/components-next/Sales/scanVisuals.js';

const props = defineProps({
  scanStatus: { type: String, default: null },
  scanScore: { type: Number, default: null },
  scanFaixa: { type: String, default: '' },
  scanPilares: { type: Object, default: () => ({}) },
  scanEvidencias: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

// Pesos maximos de cada pilar (ver Sales::Prospecting::ScanWeights::PILARES no backend --
// manter em sincronia, e' so pra desenhar a barra, nao afeta o calculo).
const PILAR_MAX = { website: 30, maps: 30, instagram: 25, icp: 15 };
const PILAR_ORDER = ['website', 'maps', 'instagram', 'icp'];
const PILAR_LABEL_KEYS = {
  website: 'CRM.LEAD.DETAIL.SCAN.PILLARS.website',
  maps: 'CRM.LEAD.DETAIL.SCAN.PILLARS.maps',
  instagram: 'CRM.LEAD.DETAIL.SCAN.PILLARS.instagram',
  icp: 'CRM.LEAD.DETAIL.SCAN.PILLARS.icp',
};
const FAIXA_LABEL_KEYS = {
  baixa_prioridade: 'CRM.LEAD.DETAIL.SCAN.FAIXA.baixa_prioridade',
  revisao_humana: 'CRM.LEAD.DETAIL.SCAN.FAIXA.revisao_humana',
  revisao_prioritaria: 'CRM.LEAD.DETAIL.SCAN.FAIXA.revisao_prioritaria',
};
const faixaBadgeClass = computed(() => scanFaixaClass(props.scanFaixa));

const faixaLabel = computed(() =>
  props.scanFaixa ? t(FAIXA_LABEL_KEYS[props.scanFaixa] || '') : ''
);

const scoreLabel = computed(() =>
  t('CRM.LEAD.DETAIL.SCAN.SCORE_OF_100', { score: props.scanScore })
);

const pilares = computed(() => {
  const list = PILAR_ORDER.map(key => {
    const value = props.scanPilares?.[key] ?? 0;
    const max = PILAR_MAX[key];
    return {
      key,
      label: t(PILAR_LABEL_KEYS[key]),
      scoreLabel: t('CRM.LEAD.DETAIL.SCAN.PILLAR_SCORE', { value, max }),
      percentage: Math.min(100, (value / max) * 100),
    };
  });

  // So o pilar mais fraco recebe Copper -- e' o ponto que pede intervencao (ver scanVisuals.js).
  const weakest = list.reduce(
    (worst, pilar) => (pilar.percentage < worst.percentage ? pilar : worst),
    list[0]
  );

  return list.map(pilar => {
    const needsAttention = pilar.key === weakest?.key;
    return {
      ...pilar,
      needsAttention,
      barClass: needsAttention
        ? SCAN_PILAR_BAR_ATTENTION_CLASS
        : SCAN_PILAR_BAR_CLASS,
      trackClass: needsAttention
        ? SCAN_PILAR_TRACK_ATTENTION_CLASS
        : SCAN_PILAR_TRACK_CLASS,
      valueClass: needsAttention
        ? SCAN_PILAR_VALUE_ATTENTION_CLASS
        : SCAN_PILAR_VALUE_CLASS,
    };
  });
});

const dadosNaoEncontrados = computed(
  () => props.scanEvidencias?.dados_nao_encontrados || []
);
const alertas = computed(() => props.scanEvidencias?.alertas || []);

const notFoundLabel = computed(() =>
  t('CRM.LEAD.DETAIL.SCAN.NOT_FOUND', {
    items: dadosNaoEncontrados.value.join(', '),
  })
);
</script>

<template>
  <div v-if="scanStatus === 'pendente'" class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-11">
      {{ t('CRM.LEAD.DETAIL.SCAN.TITLE') }}
    </span>
    <span class="flex items-center gap-2 text-xs text-n-slate-11">
      <Spinner :size="14" />
      {{ t('CRM.LEAD.DETAIL.SCAN.CALCULATING') }}
    </span>
  </div>
  <div v-else-if="scanStatus === 'erro'" class="flex flex-col gap-1">
    <span class="text-sm font-medium text-n-slate-11">
      {{ t('CRM.LEAD.DETAIL.SCAN.TITLE') }}
    </span>
    <span class="text-xs text-n-ruby-11">
      {{ t('CRM.LEAD.DETAIL.SCAN.ERROR') }}
    </span>
  </div>
  <div v-else-if="scanStatus === 'concluido'" class="flex flex-col gap-3">
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-11">
        {{ t('CRM.LEAD.DETAIL.SCAN.TITLE') }}
      </span>
      <div class="flex items-center gap-2">
        <span class="text-sm font-semibold text-n-slate-12">
          {{ scoreLabel }}
        </span>
        <span
          class="text-[11px] font-medium rounded-full px-2 py-0.5"
          :class="faixaBadgeClass"
        >
          {{ faixaLabel }}
        </span>
      </div>
    </div>
    <div class="grid grid-cols-2 gap-2">
      <div
        v-for="pilar in pilares"
        :key="pilar.key"
        class="flex flex-col gap-1 p-2 rounded-lg bg-n-alpha-1"
      >
        <div class="flex items-center justify-between">
          <span class="text-xs text-n-slate-11">{{ pilar.label }}</span>
          <span class="text-xs font-medium" :class="pilar.valueClass">
            {{ pilar.scoreLabel }}
          </span>
        </div>
        <div
          class="w-full h-1.5 rounded-full overflow-hidden"
          :class="pilar.trackClass"
        >
          <div
            class="h-full rounded-full"
            :class="pilar.barClass"
            :style="{ width: `${pilar.percentage}%` }"
          />
        </div>
      </div>
    </div>
    <div
      v-if="alertas.length"
      class="flex flex-col gap-0.5 text-xs text-n-amber-11"
    >
      <span v-for="(alerta, index) in alertas" :key="index">
        {{ alerta }}
      </span>
    </div>
    <div v-if="dadosNaoEncontrados.length" class="text-xs text-n-slate-10">
      {{ notFoundLabel }}
    </div>
  </div>
</template>
