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

  getConfigs() {
    return axios.get(`${this.url}/configs`);
  }

  createConfig(config) {
    return axios.post(`${this.url}/configs`, config);
  }

  updateConfig(id, config) {
    return axios.patch(`${this.url}/configs/${id}`, config);
  }

  deleteConfig(id) {
    return axios.delete(`${this.url}/configs/${id}`);
  }
}

export default new SalesProspectingAPI();
