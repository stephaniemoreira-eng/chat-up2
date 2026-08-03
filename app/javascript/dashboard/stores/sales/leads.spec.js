import { setActivePinia, createPinia } from 'pinia';
import SalesLeadsAPI from 'dashboard/api/sales/leads';
import { useSalesLeadsStore } from './leads';

vi.mock('dashboard/api/sales/leads', () => ({
  default: {
    get: vi.fn(),
    move: vi.fn(),
    linkConversation: vi.fn(),
    unlinkConversation: vi.fn(),
    timeline: vi.fn(),
    updateSummary: vi.fn(),
  },
}));

vi.mock('dashboard/store/utils/api', () => ({
  throwErrorMessage: vi.fn(error => {
    throw error;
  }),
}));

const createDeferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
};

describe('salesLeads store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  const seedLead = async store => {
    SalesLeadsAPI.get.mockResolvedValueOnce({
      data: {
        payload: [{ id: 1, sales_stage_id: 10, position: 0, title: 'Deal' }],
      },
    });
    await store.get({ pipelineId: 5 });
  };

  describe('#getLeadsByStage', () => {
    it('filters and orders leads by position within a stage', async () => {
      SalesLeadsAPI.get.mockResolvedValueOnce({
        data: {
          payload: [
            { id: 1, sales_stage_id: 10, position: 1 },
            { id: 2, sales_stage_id: 10, position: 0 },
            { id: 3, sales_stage_id: 11, position: 0 },
          ],
        },
      });

      const store = useSalesLeadsStore();
      await store.get({ pipelineId: 5 });

      expect(store.getLeadsByStage(10).map(lead => lead.id)).toEqual([2, 1]);
    });
  });

  describe('#move', () => {
    it('optimistically updates the stage before the request resolves', async () => {
      const deferred = createDeferred();
      SalesLeadsAPI.move.mockReturnValueOnce(deferred.promise);

      const store = useSalesLeadsStore();
      await seedLead(store);

      const movePromise = store.move({ id: 1, salesStageId: 20, position: 0 });

      // Before the API call resolves, the optimistic update is already applied.
      expect(store.getRecord(1).sales_stage_id).toBe(20);

      deferred.resolve({
        data: { payload: { id: 1, sales_stage_id: 20, position: 0 } },
      });
      await movePromise;

      expect(store.getRecord(1).sales_stage_id).toBe(20);
    });

    it('rolls back the stage and position when the move request fails', async () => {
      const deferred = createDeferred();
      SalesLeadsAPI.move.mockReturnValueOnce(deferred.promise);

      const store = useSalesLeadsStore();
      await seedLead(store);

      const movePromise = store.move({ id: 1, salesStageId: 20, position: 5 });
      expect(store.getRecord(1).sales_stage_id).toBe(20);

      deferred.reject(new Error('network error'));

      await expect(movePromise).rejects.toThrow('network error');
      expect(store.getRecord(1).sales_stage_id).toBe(10);
      expect(store.getRecord(1).position).toBe(0);
    });

    it('is a no-op when the lead is not found locally', async () => {
      const store = useSalesLeadsStore();
      const result = await store.move({ id: 999, salesStageId: 20 });

      expect(result).toBeNull();
      expect(SalesLeadsAPI.move).not.toHaveBeenCalled();
    });
  });

  describe('#linkConversation', () => {
    it('replaces the local record with the response payload', async () => {
      const store = useSalesLeadsStore();
      await seedLead(store);

      SalesLeadsAPI.linkConversation.mockResolvedValueOnce({
        data: { payload: { id: 1, sales_stage_id: 10, position: 0 } },
      });

      await store.linkConversation({ id: 1, conversationId: 42 });

      expect(SalesLeadsAPI.linkConversation).toHaveBeenCalledWith(1, 42);
    });
  });

  describe('#fetchTimeline', () => {
    it('returns the timeline payload from the API', async () => {
      SalesLeadsAPI.timeline.mockResolvedValueOnce({
        data: { payload: { entries: [{ id: 1, type: 'activity' }], next_before: null } },
      });

      const store = useSalesLeadsStore();
      const payload = await store.fetchTimeline({ id: 1, before: 123 });

      expect(SalesLeadsAPI.timeline).toHaveBeenCalledWith(1, { before: 123 });
      expect(payload.entries).toHaveLength(1);
    });
  });

  describe('#updateSummary', () => {
    it('replaces the local record with the updated summary', async () => {
      const store = useSalesLeadsStore();
      await seedLead(store);

      SalesLeadsAPI.updateSummary.mockResolvedValueOnce({
        data: { payload: { id: 1, sales_stage_id: 10, position: 0, summary: 'Novo resumo' } },
      });

      await store.updateSummary({ id: 1, summary: 'Novo resumo' });

      expect(SalesLeadsAPI.updateSummary).toHaveBeenCalledWith(1, 'Novo resumo');
      expect(store.getRecord(1).summary).toBe('Novo resumo');
    });
  });
});
