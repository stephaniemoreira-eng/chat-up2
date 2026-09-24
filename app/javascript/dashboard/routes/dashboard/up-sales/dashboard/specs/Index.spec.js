import { mount, flushPromises } from '@vue/test-utils';
import DashboardIndex from '../Index.vue';
import ProspectDashboardAPI from 'dashboard/api/sales/prospectDashboard';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('dashboard/api/sales/leads', () => ({
  default: {
    summary: vi.fn(() =>
      Promise.resolve({
        data: { leads_count: 4, deals_won_count: 2, last_search_at: null },
      })
    ),
  },
}));

vi.mock('dashboard/api/upSales/calendarEvents', () => ({
  default: { list: vi.fn(() => Promise.reject(new Error('no calendar'))) },
}));

const payload = {
  coorte: {
    data_inicial: '2026-09-01',
    data_final: '2026-09-30',
    modo: 'consolidado',
  },
  big_numbers: {
    leads_iniciados: 5,
    em_conversa: { absoluto: 4, taxa: 0.8 },
    qualificados: { absoluto: 2, taxa: 0.4 },
    convertidos: { absoluto: 1, taxa: 0.2 },
  },
  funil: {
    etapas: [
      { marco: 'iniciaram', absoluto: 5, eficiencia: null },
      { marco: 'em_conversa', absoluto: 4, eficiencia: 0.8 },
      { marco: 'qualificados', absoluto: 2, eficiencia: 0.5 },
      { marco: 'convertidos', absoluto: 1, eficiencia: 0.5 },
    ],
    composicao_conversao: { agendamento: 1, callback: 0 },
  },
  tempos_medios: {
    entrada_ate_em_conversa: { media_segundos: 2400, amostra: 3 },
    em_conversa_ate_qualificacao: { media_segundos: 126000, amostra: 2 },
    qualificacao_ate_conversao: { media_segundos: null, amostra: 0 },
    entrada_ate_conversao: { media_segundos: 259200, amostra: 1 },
  },
  recovery: {
    precisaram: 1,
    recuperados: 1,
    taxa_recovery: 0.2,
    taxa_sucesso: 1,
    conversoes_apos_recovery: 1,
  },
  opcoes_filtro: {
    origens_lead: ['busca_prospeccao'],
    segmentos: ['hotel'],
    inboxes_entrada: [{ id: 7, nome: 'Prospecção' }],
  },
};

describe('Up Sales Dashboard', () => {
  beforeEach(() => {
    vi.spyOn(ProspectDashboardAPI, 'show').mockResolvedValue({
      data: payload,
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders the cohort computed by the backend without recomputing it', async () => {
    const wrapper = mount(DashboardIndex);
    await flushPromises();

    const text = wrapper.text();
    expect(ProspectDashboardAPI.show).toHaveBeenCalledTimes(1);
    expect(text).toContain('80%');
    expect(text).toContain(
      'UP_SALES.DASHBOARD.PROSPECT.DURATION.MINUTES {"m":40}'
    );
    expect(text).toContain(
      'UP_SALES.DASHBOARD.PROSPECT.DURATION.DAYS {"d":1,"h":11}'
    );
    expect(text).toContain('UP_SALES.DASHBOARD.PROSPECT.EMPTY_VALUE');
    expect(text).toContain('Prospecção');
  });

  it('refetches the same cohort endpoint when an official filter changes', async () => {
    const wrapper = mount(DashboardIndex);
    await flushPromises();

    await wrapper.findAll('select')[0].setValue('inbound');
    await flushPromises();

    expect(ProspectDashboardAPI.show).toHaveBeenCalledTimes(2);
    expect(ProspectDashboardAPI.show).toHaveBeenLastCalledWith(
      expect.objectContaining({
        modo: 'inbound',
        dataInicial: '2026-09-01',
        dataFinal: '2026-09-30',
      })
    );
  });
});
