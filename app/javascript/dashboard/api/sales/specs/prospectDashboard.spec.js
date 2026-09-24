import prospectDashboardAPI from '../prospectDashboard';
import ApiClient from '../../ApiClient';

describe('#ProspectDashboardAPI', () => {
  it('creates correct instance', () => {
    expect(prospectDashboardAPI).toBeInstanceOf(ApiClient);
    expect(prospectDashboardAPI).toHaveProperty('show');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = { get: vi.fn(() => Promise.resolve()) };

    beforeEach(() => {
      window.axios = axiosMock;
      axiosMock.get.mockClear();
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#show sends only the official filters', () => {
      prospectDashboardAPI.show({
        dataInicial: '2026-09-01',
        dataFinal: '2026-09-30',
        modo: 'inbound',
        origemLead: 'busca_prospeccao',
        segmento: 'hotel',
        inboxEntradaId: 7,
      });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/crm/prospect_dashboard?data_inicial=2026-09-01&data_final=2026-09-30&modo=inbound&origem_lead=busca_prospeccao&segmento=hotel&inbox_entrada_id=7'
      );
    });

    it('#show omits blank filters', () => {
      prospectDashboardAPI.show({ modo: 'consolidado', segmento: '' });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/crm/prospect_dashboard?modo=consolidado'
      );
    });
  });
});
