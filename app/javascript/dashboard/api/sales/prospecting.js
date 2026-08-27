/* global axios */
import ApiClient from '../ApiClient';

class SalesProspectingAPI extends ApiClient {
  constructor() {
    super('crm/prospecting', { accountScoped: true });
  }

  search(query) {
    return axios.post(`${this.url}/search`, { query });
  }

  createLeads({ pipelineId, salesStageId, results }) {
    return axios.post(`${this.url}/create_leads`, {
      pipeline_id: pipelineId,
      sales_stage_id: salesStageId,
      results,
    });
  }
}

export default new SalesProspectingAPI();
