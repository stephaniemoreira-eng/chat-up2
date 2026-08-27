/* global axios */
import ApiClient from '../ApiClient';

class SalesProspectingAPI extends ApiClient {
  constructor() {
    super('crm/prospecting', { accountScoped: true });
  }

  search(filters) {
    return axios.post(`${this.url}/search`, filters);
  }

  createLeads({ pipelineId, salesStageId, resultIds }) {
    return axios.post(`${this.url}/create_leads`, {
      pipeline_id: pipelineId,
      sales_stage_id: salesStageId,
      result_ids: resultIds,
    });
  }
}

export default new SalesProspectingAPI();
