<script>
// <script setup> não aceita export de módulo -- EMPTY_FILTERS precisa ficar num bloco <script>
// comum, à parte, exatamente pelo motivo documentado pelo Vue pra esse padrão: é o estado
// inicial dos filtros, e CrmIndex.vue precisa dele pra inicializar/resetar sem duplicar a lista
// dos sete campos noutro arquivo.
export const EMPTY_FILTERS = {
  modoEntrada: '',
  origemLead: '',
  segmento: '',
  inboxAtualId: '',
  modoAtendimento: '',
  responsavelAtualId: '',
  recuperacaoStatus: '',
};
</script>

<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Os sete filtros do §21.1 -- lêem custom_attributes.engine_filters, que
// OperationalEngine::SalesProjectionSync grava a cada sincronização (ver o backend). Filtragem
// inteiramente client-side sobre os leads já carregados: Sales::* já é uma projeção
// autossuficiente (§5.2/§5.3), não faz sentido essa tela ir ao Supabase de novo só pra filtrar
// o que já veio junto no card.
const props = defineProps({
  modelValue: { type: Object, required: true },
  leads: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const ALL_VALUE = '';

const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const setFilter = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value ?? ALL_VALUE });
};

const withAllOption = options => [
  { value: ALL_VALUE, label: t('CRM.FILTERS.ALL') },
  ...options,
];

const modoEntradaOptions = computed(() =>
  withAllOption([
    { value: 'outbound', label: t('CRM.FILTERS.MODO_ENTRADA.OUTBOUND') },
    { value: 'inbound', label: t('CRM.FILTERS.MODO_ENTRADA.INBOUND') },
  ])
);

const origemLeadOptions = computed(() =>
  withAllOption([
    {
      value: 'google_scraping',
      label: t('CRM.FILTERS.ORIGEM_LEAD.GOOGLE_SCRAPING'),
    },
    { value: 'cnae', label: t('CRM.FILTERS.ORIGEM_LEAD.CNAE') },
    { value: 'csv', label: t('CRM.FILTERS.ORIGEM_LEAD.CSV') },
    { value: 'google_ads', label: t('CRM.FILTERS.ORIGEM_LEAD.GOOGLE_ADS') },
    { value: 'site', label: t('CRM.FILTERS.ORIGEM_LEAD.SITE') },
    {
      value: 'inbound_direto',
      label: t('CRM.FILTERS.ORIGEM_LEAD.INBOUND_DIRETO'),
    },
    { value: 'outro', label: t('CRM.FILTERS.ORIGEM_LEAD.OUTRO') },
  ])
);

const modoAtendimentoOptions = computed(() =>
  withAllOption([
    { value: 'lavinia', label: t('CRM.LEAD.ENGINE_TAGS.LAVINIA') },
    { value: 'humano', label: t('CRM.LEAD.ENGINE_TAGS.HUMANO') },
  ])
);

const recuperacaoStatusOptions = computed(() =>
  withAllOption([
    {
      value: 'inativa',
      label: t('CRM.FILTERS.RECUPERACAO_STATUS.INATIVA'),
    },
    { value: 'ativa', label: t('CRM.FILTERS.RECUPERACAO_STATUS.ATIVA') },
  ])
);

const inboxOptions = computed(() =>
  withAllOption(
    inboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name }))
  )
);

const agentOptions = computed(() =>
  withAllOption(
    agents.value.map(agent => ({ value: agent.id, label: agent.name }))
  )
);

// Texto livre vindo da Busca/Prospecção (ex.: "cafeteria", "clínica odontológica") -- em vez de
// um campo de texto (sujeito a erro de digitação e plural/singular), lista só os valores que já
// aparecem nos leads carregados agora. Some da lista sozinho quando nenhum lead do board tem
// mais aquele segmento -- não precisa de tela própria de manutenção.
const segmentoOptions = computed(() => {
  const values = [
    ...new Set(
      props.leads
        .map(lead => lead.custom_attributes?.engine_filters?.segmento)
        .filter(Boolean)
    ),
  ].sort();
  return withAllOption(values.map(value => ({ value, label: value })));
});

const hasActiveFilters = computed(() =>
  Object.values(props.modelValue).some(value => value !== ALL_VALUE)
);

const clearFilters = () => emit('update:modelValue', { ...EMPTY_FILTERS });
</script>

<template>
  <div class="flex flex-wrap items-end gap-2 px-4 py-2 border-b border-n-weak">
    <div class="flex flex-col gap-1 w-36">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.MODO_ENTRADA.LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.modoEntrada"
        :options="modoEntradaOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('modoEntrada', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-40">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.ORIGEM_LEAD.LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.origemLead"
        :options="origemLeadOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('origemLead', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-40">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.SEGMENTO_LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.segmento"
        :options="segmentoOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('segmento', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-40">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.INBOX_LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.inboxAtualId"
        :options="inboxOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('inboxAtualId', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-36">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.MODO_ATENDIMENTO_LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.modoAtendimento"
        :options="modoAtendimentoOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('modoAtendimento', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-40">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.RESPONSAVEL_LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.responsavelAtualId"
        :options="agentOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('responsavelAtualId', value)"
      />
    </div>
    <div class="flex flex-col gap-1 w-40">
      <label class="text-xs font-medium text-n-slate-11">
        {{ t('CRM.FILTERS.RECUPERACAO_STATUS.LABEL') }}
      </label>
      <ComboBox
        :model-value="modelValue.recuperacaoStatus"
        :options="recuperacaoStatusOptions"
        :placeholder="t('CRM.FILTERS.ALL')"
        @update:model-value="value => setFilter('recuperacaoStatus', value)"
      />
    </div>
    <Button
      v-if="hasActiveFilters"
      icon="i-lucide-x"
      color="slate"
      variant="ghost"
      size="sm"
      :label="t('CRM.FILTERS.CLEAR')"
      @click="clearFilters"
    />
  </div>
</template>
