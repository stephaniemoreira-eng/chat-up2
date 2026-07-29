/* global axios */
import ApiClient from '../ApiClient';

class SalesStagesAPI extends ApiClient {
  constructor() {
    // Stages are nested under a pipeline (`crm/pipelines/:pipeline_id/stages`), so every method
    // here takes the pipeline id explicitly rather than relying on the base `url` getter.
    super('crm/pipelines', { accountScoped: true });
  }

  stagesUrl(pipelineId) {
    return `${this.url}/${pipelineId}/stages`;
  }

  get(pipelineId) {
    return axios.get(this.stagesUrl(pipelineId));
  }

  show(pipelineId, id) {
    return axios.get(`${this.stagesUrl(pipelineId)}/${id}`);
  }

  create(pipelineId, data) {
    return axios.post(this.stagesUrl(pipelineId), data);
  }

  update(pipelineId, id, data) {
    return axios.patch(`${this.stagesUrl(pipelineId)}/${id}`, data);
  }

  delete(pipelineId, id) {
    return axios.delete(`${this.stagesUrl(pipelineId)}/${id}`);
  }

  reorder(pipelineId, positionsHash) {
    return axios.post(`${this.stagesUrl(pipelineId)}/reorder`, {
      positions_hash: positionsHash,
    });
  }
}

export default new SalesStagesAPI();
