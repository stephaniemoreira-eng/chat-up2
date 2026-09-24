/* global axios */
import ApiClient from '../ApiClient';

// CP-11 (SSOT §22): Dashboard Prospect por coorte, calculado no backend sobre o Engine.
// Só os filtros oficiais do §22.3 são enviados.
class ProspectDashboardAPI extends ApiClient {
  constructor() {
    super('crm/prospect_dashboard', { accountScoped: true });
  }

  show({
    dataInicial,
    dataFinal,
    modo,
    origemLead,
    segmento,
    inboxEntradaId,
  } = {}) {
    const query = new URLSearchParams(
      Object.entries({
        data_inicial: dataInicial,
        data_final: dataFinal,
        modo,
        origem_lead: origemLead,
        segmento,
        inbox_entrada_id: inboxEntradaId,
      }).filter(
        ([, value]) => value !== undefined && value !== null && value !== ''
      )
    ).toString();
    return axios.get(query ? `${this.url}?${query}` : this.url);
  }
}

export default new ProspectDashboardAPI();
