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
}

export default new SalesLeadsAPI();
