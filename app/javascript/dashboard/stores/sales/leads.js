import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import SalesLeadsAPI from 'dashboard/api/sales/leads';

export const useSalesLeadsStore = createStore({
  name: 'salesLeads',
  type: 'pinia',
  API: SalesLeadsAPI,
  getters: {
    getLeadsByStage: state => stageId =>
      state.records
        .filter(lead => lead.sales_stage_id === Number(stageId))
        .sort((a, b) => a.position - b.position),
  },
  actions: () => ({
    async get({ pipelineId } = {}) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await SalesLeadsAPI.get({ pipelineId });
        this.records = data.payload || data;
        return this.records;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    // Optimistically moves the lead to its new stage/position so the drag feels instant, then
    // confirms with the backend. On failure the previous stage/position are restored so the
    // board doesn't silently drift from what the server actually persisted.
    async move({ id, salesStageId, position }) {
      const record = this.records.find(lead => lead.id === id);
      if (!record) return null;

      const previousStageId = record.sales_stage_id;
      const previousPosition = record.position;

      record.sales_stage_id = Number(salesStageId);
      record.position = position;

      try {
        const { data } = await SalesLeadsAPI.move(id, {
          salesStageId,
          position,
        });
        const updated = data.payload || data;
        const index = this.records.findIndex(lead => lead.id === id);
        if (index !== -1) this.records[index] = updated;
        return updated;
      } catch (error) {
        record.sales_stage_id = previousStageId;
        record.position = previousPosition;
        return throwErrorMessage(error);
      }
    },

    async linkConversation({ id, conversationId }) {
      const { data } = await SalesLeadsAPI.linkConversation(id, conversationId);
      const updated = data.payload || data;
      const index = this.records.findIndex(lead => lead.id === id);
      if (index !== -1) this.records[index] = updated;
      return updated;
    },

    async unlinkConversation({ id, conversationId }) {
      await SalesLeadsAPI.unlinkConversation(id, conversationId);
    },
  }),
});
