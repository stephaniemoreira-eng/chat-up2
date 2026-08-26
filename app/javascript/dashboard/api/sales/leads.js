/* global axios */
import ApiClient from '../ApiClient';

const buildParams = params =>
  new URLSearchParams(
    Object.entries(params).filter(
      ([, value]) => value !== undefined && value !== ''
    )
  ).toString();

class SalesLeadsAPI extends ApiClient {
  constructor() {
    super('crm/leads', { accountScoped: true });
  }

  get(params = {}) {
    const { pipelineId, stageId, assigneeId } = params;
    const query = buildParams({
      pipeline_id: pipelineId,
      stage_id: stageId,
      assignee_id: assigneeId,
    });
    return axios.get(`${this.url}?${query}`);
  }

  move(id, { salesStageId, position }) {
    return axios.post(`${this.url}/${id}/move`, {
      sales_stage_id: salesStageId,
      position,
    });
  }

  linkConversation(id, conversationId) {
    return axios.post(`${this.url}/${id}/link_conversation`, {
      conversation_id: conversationId,
    });
  }

  unlinkConversation(id, conversationId) {
    return axios.delete(`${this.url}/${id}/unlink_conversation`, {
      data: { conversation_id: conversationId },
    });
  }

  timeline(id, { before, perPage } = {}) {
    const query = buildParams({ before, per_page: perPage });
    return axios.get(`${this.url}/${id}/timeline?${query}`);
  }

  updateSummary(id, summary) {
    return axios.patch(`${this.url}/${id}/update_summary`, { summary });
  }

  summary() {
    return axios.get(`${this.url}/summary`);
  }
}

export default new SalesLeadsAPI();
