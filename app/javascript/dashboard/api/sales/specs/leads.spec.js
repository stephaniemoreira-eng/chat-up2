import salesLeadsAPI from '../leads';
import ApiClient from '../../ApiClient';

describe('#SalesLeadsAPI', () => {
  it('creates correct instance', () => {
    expect(salesLeadsAPI).toBeInstanceOf(ApiClient);
    expect(salesLeadsAPI).toHaveProperty('get');
    expect(salesLeadsAPI).toHaveProperty('create');
    expect(salesLeadsAPI).toHaveProperty('update');
    expect(salesLeadsAPI).toHaveProperty('delete');
    expect(salesLeadsAPI).toHaveProperty('move');
    expect(salesLeadsAPI).toHaveProperty('linkConversation');
    expect(salesLeadsAPI).toHaveProperty('unlinkConversation');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#get filters by pipeline, stage and assignee', () => {
      salesLeadsAPI.get({ pipelineId: 1, stageId: 2, assigneeId: 3 });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/crm/leads?pipeline_id=1&stage_id=2&assignee_id=3'
      );
    });

    it('#get omits blank filters', () => {
      salesLeadsAPI.get({ pipelineId: 1 });
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/crm/leads?pipeline_id=1'
      );
    });

    it('#move posts the destination stage and position', () => {
      salesLeadsAPI.move(1, { salesStageId: 2, position: 0.5 });
      expect(axiosMock.post).toHaveBeenCalledWith('/api/v1/crm/leads/1/move', {
        sales_stage_id: 2,
        position: 0.5,
      });
    });

    it('#linkConversation posts the conversation id', () => {
      salesLeadsAPI.linkConversation(1, 42);
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/crm/leads/1/link_conversation',
        { conversation_id: 42 }
      );
    });

    it('#unlinkConversation sends the conversation id as delete body', () => {
      salesLeadsAPI.unlinkConversation(1, 42);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/crm/leads/1/unlink_conversation',
        { data: { conversation_id: 42 } }
      );
    });
  });
});
