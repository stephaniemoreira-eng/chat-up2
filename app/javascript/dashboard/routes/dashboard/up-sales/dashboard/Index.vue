<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadsAPI from 'dashboard/api/sales/leads';
import ProspectDashboardAPI from 'dashboard/api/sales/prospectDashboard';
import CalendarEventsAPI from 'dashboard/api/upSales/calendarEvents';

const { t } = useI18n();

const isLoading = ref(true);
const leadsCount = ref(0);
const dealsWonCount = ref(0);
const lastSearchAt = ref(null);
const meetingsScheduledCount = ref(null);

// CP-11 (SSOT §22): Dashboard Prospect por coorte. Toda a conta é feita no backend, sobre o
// Engine; aqui só entram os filtros oficiais do §22.3 e a apresentação.
const modoOptions = computed(() => [
  {
    value: 'consolidado',
    label: t('UP_SALES.DASHBOARD.PROSPECT.MODES.CONSOLIDADO'),
  },
  { value: 'outbound', label: t('UP_SALES.DASHBOARD.PROSPECT.MODES.OUTBOUND') },
  { value: 'inbound', label: t('UP_SALES.DASHBOARD.PROSPECT.MODES.INBOUND') },
]);
const filtros = reactive({
  dataInicial: '',
  dataFinal: '',
  modo: 'consolidado',
  origemLead: '',
  segmento: '',
  inboxEntradaId: '',
});
const prospect = ref(null);
const prospectLoading = ref(true);
const prospectError = ref(false);

const formatDate = iso => {
  if (!iso) return t('UP_SALES.DASHBOARD.LAST_SEARCH_EMPTY');
  return new Date(iso).toLocaleDateString('pt-BR');
};

const emptyValue = () => t('UP_SALES.DASHBOARD.PROSPECT.EMPTY_VALUE');

const formatRate = rate => {
  if (rate === null || rate === undefined) return emptyValue();
  return `${(rate * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
};

const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return emptyValue();
  const totalMinutes = Math.round(seconds / 60);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) {
    return t('UP_SALES.DASHBOARD.PROSPECT.DURATION.DAYS', {
      d: days,
      h: hours,
    });
  }
  if (hours > 0) {
    return t('UP_SALES.DASHBOARD.PROSPECT.DURATION.HOURS', {
      h: hours,
      m: minutes,
    });
  }
  return t('UP_SALES.DASHBOARD.PROSPECT.DURATION.MINUTES', { m: minutes });
};

const bigNumbers = computed(() => {
  const data = prospect.value?.big_numbers;
  if (!data) return [];
  return [
    {
      key: 'started',
      label: t('UP_SALES.DASHBOARD.PROSPECT.BIG_NUMBERS.STARTED'),
      value: data.leads_iniciados,
      detail: null,
    },
    {
      key: 'conversation',
      label: t('UP_SALES.DASHBOARD.PROSPECT.BIG_NUMBERS.CONVERSATION_RATE'),
      value: formatRate(data.em_conversa.taxa),
      detail: data.em_conversa.absoluto,
    },
    {
      key: 'qualification',
      label: t('UP_SALES.DASHBOARD.PROSPECT.BIG_NUMBERS.QUALIFICATION_RATE'),
      value: formatRate(data.qualificados.taxa),
      detail: data.qualificados.absoluto,
    },
    {
      key: 'conversion',
      label: t('UP_SALES.DASHBOARD.PROSPECT.BIG_NUMBERS.CONVERSION_RATE'),
      value: formatRate(data.convertidos.taxa),
      detail: data.convertidos.absoluto,
    },
  ];
});

const funnelStages = computed(() => {
  const etapas = prospect.value?.funil?.etapas || [];
  const top = etapas[0]?.absoluto || 0;
  const labels = {
    iniciaram: t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.INICIARAM'),
    em_conversa: t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.EM_CONVERSA'),
    qualificados: t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.QUALIFICADOS'),
    convertidos: t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.CONVERTIDOS'),
  };
  return etapas.map(etapa => ({
    ...etapa,
    label: labels[etapa.marco],
    width: top > 0 ? Math.round((etapa.absoluto / top) * 100) : 0,
  }));
});

const averageTimes = computed(() => {
  const data = prospect.value?.tempos_medios;
  if (!data) return [];
  return [
    [
      'entrada_ate_em_conversa',
      t('UP_SALES.DASHBOARD.PROSPECT.TIMES.ENTRY_TO_CONVERSATION'),
    ],
    [
      'em_conversa_ate_qualificacao',
      t('UP_SALES.DASHBOARD.PROSPECT.TIMES.CONVERSATION_TO_QUALIFICATION'),
    ],
    [
      'qualificacao_ate_conversao',
      t('UP_SALES.DASHBOARD.PROSPECT.TIMES.QUALIFICATION_TO_CONVERSION'),
    ],
    [
      'entrada_ate_conversao',
      t('UP_SALES.DASHBOARD.PROSPECT.TIMES.ENTRY_TO_CONVERSION'),
    ],
  ].map(([key, label]) => ({
    key,
    label,
    value: formatDuration(data[key].media_segundos),
    sample: data[key].amostra,
  }));
});

const recoveryStats = computed(() => {
  const data = prospect.value?.recovery;
  if (!data) return [];
  return [
    {
      key: 'needed',
      label: t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.NEEDED'),
      value: data.precisaram,
    },
    {
      key: 'recovered',
      label: t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.RECOVERED'),
      value: data.recuperados,
    },
    {
      key: 'rate',
      label: t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.RATE'),
      value: formatRate(data.taxa),
    },
    {
      key: 'after',
      label: t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.CONVERSIONS_AFTER'),
      value: data.conversoes_apos_recovery,
    },
  ];
});

const filterOptions = computed(
  () =>
    prospect.value?.opcoes_filtro || {
      origens_lead: [],
      segmentos: [],
      inboxes_entrada: [],
    }
);

let prospectRequestId = 0;

const fetchProspect = async () => {
  prospectRequestId += 1;
  const requestId = prospectRequestId;
  prospectLoading.value = true;
  prospectError.value = false;
  try {
    const { data } = await ProspectDashboardAPI.show({ ...filtros });
    if (requestId !== prospectRequestId) return;
    prospect.value = data;
    // Sem período escolhido, o backend usa o mês corrente (America/Sao_Paulo) -- reflete aqui.
    filtros.dataInicial = data.coorte.data_inicial;
    filtros.dataFinal = data.coorte.data_final;
  } catch {
    if (requestId !== prospectRequestId) return;
    prospectError.value = true;
  } finally {
    if (requestId === prospectRequestId) prospectLoading.value = false;
  }
};

let meetingsRequestId = 0;

const fetchMeetingsScheduledThisMonth = async () => {
  meetingsRequestId += 1;
  const requestId = meetingsRequestId;
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  try {
    const { data } = await CalendarEventsAPI.list({
      timeMin: monthStart.toISOString(),
      timeMax: monthEnd.toISOString(),
      maxResults: 50,
    });
    // Ignore responses from a stale/overlapping call — otherwise a slower, out-of-order
    // response (e.g. a transient 401 on a duplicate request) can clobber a newer result.
    if (requestId !== meetingsRequestId) return;
    meetingsScheduledCount.value = (data.payload || []).length;
  } catch {
    if (requestId !== meetingsRequestId) return;
    // No calendar connected yet, or up2-agents unreachable — leave the placeholder dash instead
    // of a scary error on a dashboard tile.
    meetingsScheduledCount.value = null;
  }
};

watch(
  () => [
    filtros.dataInicial,
    filtros.dataFinal,
    filtros.modo,
    filtros.origemLead,
    filtros.segmento,
    filtros.inboxEntradaId,
  ],
  (current, previous) => {
    // A primeira resposta preenche o período padrão; isso não precisa de nova consulta.
    const onlyDefaultsFilled =
      previous[0] === '' &&
      previous[1] === '' &&
      current.slice(2).every((value, index) => value === previous[index + 2]);
    if (!onlyDefaultsFilled) fetchProspect();
  }
);

onMounted(async () => {
  fetchProspect();
  try {
    const { data } = await LeadsAPI.summary();
    leadsCount.value = data.leads_count;
    dealsWonCount.value = data.deals_won_count;
    lastSearchAt.value = data.last_search_at;
  } finally {
    isLoading.value = false;
  }
  fetchMeetingsScheduledThisMonth();
});
</script>

<template>
  <div class="p-6 flex flex-col gap-8">
    <h1 class="text-xl font-semibold text-n-slate-12">
      {{ t('UP_SALES.DASHBOARD.TITLE') }}
    </h1>

    <section class="flex flex-col gap-4">
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.HINT') }}
        </p>
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.START') }}
          <input
            v-model="filtros.dataInicial"
            type="date"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.END') }}
          <input
            v-model="filtros.dataFinal"
            type="date"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.MODE') }}
          <select
            v-model="filtros.modo"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          >
            <option
              v-for="modo in modoOptions"
              :key="modo.value"
              :value="modo.value"
            >
              {{ modo.label }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.ORIGIN') }}
          <select
            v-model="filtros.origemLead"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          >
            <option value="">
              {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.ALL') }}
            </option>
            <option
              v-for="origem in filterOptions.origens_lead"
              :key="origem"
              :value="origem"
            >
              {{ origem }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.SEGMENT') }}
          <select
            v-model="filtros.segmento"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          >
            <option value="">
              {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.ALL') }}
            </option>
            <option
              v-for="segmento in filterOptions.segmentos"
              :key="segmento"
              :value="segmento"
            >
              {{ segmento }}
            </option>
          </select>
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.INBOX') }}
          <select
            v-model="filtros.inboxEntradaId"
            class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1.5 text-sm text-n-slate-12"
          >
            <option value="">
              {{ t('UP_SALES.DASHBOARD.PROSPECT.FILTERS.ALL') }}
            </option>
            <option
              v-for="inbox in filterOptions.inboxes_entrada"
              :key="inbox.id"
              :value="String(inbox.id)"
            >
              {{ inbox.nome || `#${inbox.id}` }}
            </option>
          </select>
        </label>
      </div>

      <p v-if="prospectError" class="text-sm text-n-ruby-11">
        {{ t('UP_SALES.DASHBOARD.PROSPECT.ERROR') }}
      </p>
      <p
        v-else-if="prospectLoading && !prospect"
        class="text-sm text-n-slate-11"
      >
        {{ t('UP_SALES.DASHBOARD.PROSPECT.LOADING') }}
      </p>

      <template v-if="prospect && !prospectError">
        <div
          class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4"
          :class="{ 'opacity-60': prospectLoading }"
        >
          <div
            v-for="card in bigNumbers"
            :key="card.key"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-5"
          >
            <p class="text-sm text-n-slate-11">{{ card.label }}</p>
            <p class="text-2xl font-semibold text-n-slate-12 mt-2">
              {{ card.value }}
            </p>
            <p v-if="card.detail !== null" class="text-xs text-n-slate-11 mt-1">
              {{
                t('UP_SALES.DASHBOARD.PROSPECT.BIG_NUMBERS.ABSOLUTE', {
                  count: card.detail,
                })
              }}
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
            <h3 class="text-sm font-semibold text-n-slate-12 mb-4">
              {{ t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.TITLE') }}
            </h3>
            <ul class="flex flex-col gap-3">
              <li v-for="etapa in funnelStages" :key="etapa.marco">
                <div class="flex items-baseline justify-between text-sm">
                  <span class="text-n-slate-12">{{ etapa.label }}</span>
                  <span class="font-semibold text-n-slate-12">
                    {{ etapa.absoluto }}
                  </span>
                </div>
                <div class="h-2 rounded bg-n-alpha-2 mt-1">
                  <div
                    class="h-2 rounded bg-n-brand"
                    :style="{ width: `${etapa.width}%` }"
                  />
                </div>
                <p
                  v-if="etapa.eficiencia !== null"
                  class="text-xs text-n-slate-11 mt-1"
                >
                  {{
                    t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.EFFICIENCY', {
                      rate: formatRate(etapa.eficiencia),
                    })
                  }}
                </p>
              </li>
            </ul>
            <p class="text-xs text-n-slate-11 mt-4">
              {{
                t('UP_SALES.DASHBOARD.PROSPECT.FUNNEL.COMPOSITION', {
                  meetings: prospect.funil.composicao_conversao.agendamento,
                  callbacks: prospect.funil.composicao_conversao.callback,
                })
              }}
            </p>
          </div>

          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
            <h3 class="text-sm font-semibold text-n-slate-12 mb-4">
              {{ t('UP_SALES.DASHBOARD.PROSPECT.TIMES.TITLE') }}
            </h3>
            <ul class="flex flex-col gap-3">
              <li v-for="item in averageTimes" :key="item.key">
                <div class="flex items-baseline justify-between text-sm">
                  <span class="text-n-slate-12">{{ item.label }}</span>
                  <span class="font-semibold text-n-slate-12">
                    {{ item.value }}
                  </span>
                </div>
                <p class="text-xs text-n-slate-11">
                  {{
                    t('UP_SALES.DASHBOARD.PROSPECT.TIMES.SAMPLE', {
                      count: item.sample,
                    })
                  }}
                </p>
              </li>
            </ul>
          </div>
        </div>

        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-3">
            {{ t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.TITLE') }}
          </h3>
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
            <div v-for="stat in recoveryStats" :key="stat.key">
              <p class="text-xs text-n-slate-11">{{ stat.label }}</p>
              <p class="text-lg font-semibold text-n-slate-12">
                {{ stat.value }}
              </p>
            </div>
          </div>
          <p class="text-xs text-n-slate-11 mt-3">
            {{ t('UP_SALES.DASHBOARD.PROSPECT.RECOVERY.HINT') }}
          </p>
        </div>
      </template>
    </section>

    <section class="flex flex-col gap-4">
      <div>
        <h2 class="text-base font-semibold text-n-slate-12">
          {{ t('UP_SALES.DASHBOARD.CRM_SECTION_TITLE') }}
        </h2>
        <p class="text-sm text-n-slate-11 mt-1">
          {{ t('UP_SALES.DASHBOARD.CRM_SECTION_HINT') }}
        </p>
      </div>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
          <p class="text-sm text-n-slate-11">
            {{ t('UP_SALES.DASHBOARD.LEADS_COUNT') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12 mt-2">
            {{ isLoading ? '…' : leadsCount }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
          <p class="text-sm text-n-slate-11">
            {{ t('UP_SALES.DASHBOARD.LAST_SEARCH') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12 mt-2">
            {{ isLoading ? '…' : formatDate(lastSearchAt) }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
          <p class="text-sm text-n-slate-11">
            {{ t('UP_SALES.DASHBOARD.MEETINGS_SCHEDULED') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12 mt-2">
            {{
              meetingsScheduledCount === null
                ? t('UP_SALES.DASHBOARD.MEETINGS_PLACEHOLDER')
                : meetingsScheduledCount
            }}
          </p>
        </div>
        <div class="rounded-lg border border-n-weak bg-n-solid-1 p-5">
          <p class="text-sm text-n-slate-11">
            {{ t('UP_SALES.DASHBOARD.DEALS_WON') }}
          </p>
          <p class="text-2xl font-semibold text-n-slate-12 mt-2">
            {{ isLoading ? '…' : dealsWonCount }}
          </p>
        </div>
      </div>
    </section>
  </div>
</template>
