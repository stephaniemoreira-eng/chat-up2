import { createStore } from 'dashboard/store/storeFactory';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import SalesStagesAPI from 'dashboard/api/sales/stages';

export const useSalesStagesStore = createStore({
  name: 'salesStages',
  type: 'pinia',
  API: SalesStagesAPI,
  getters: {
    getStagesByPipeline: state => pipelineId =>
      state.records
        .filter(stage => stage.sales_pipeline_id === Number(pipelineId))
        .sort((a, b) => a.position - b.position),
  },
  actions: () => ({
    async get(pipelineId) {
      this.setUIFlag({ fetchingList: true });
      try {
        const { data } = await SalesStagesAPI.get(pipelineId);
        const stages = data.payload || data;
        this.records = [
          ...this.records.filter(
            stage => stage.sales_pipeline_id !== Number(pipelineId)
          ),
          ...stages,
        ];
        return stages;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingList: false });
      }
    },

    async create({ pipelineId, ...stageAttrs }) {
      this.setUIFlag({ creatingItem: true });
      try {
        const { data } = await SalesStagesAPI.create(pipelineId, stageAttrs);
        const stage = data.payload || data;
        this.records.push(stage);
        return stage;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingItem: false });
      }
    },

    async update({ pipelineId, id, ...stageAttrs }) {
      this.setUIFlag({ updatingItem: true });
      try {
        const { data } = await SalesStagesAPI.update(
          pipelineId,
          id,
          stageAttrs
        );
        const stage = data.payload || data;
        const index = this.records.findIndex(r => r.id === stage.id);
        if (index !== -1) this.records[index] = stage;
        return stage;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingItem: false });
      }
    },

    async delete({ pipelineId, id }) {
      this.setUIFlag({ deletingItem: true });
      try {
        await SalesStagesAPI.delete(pipelineId, id);
        this.records = this.records.filter(record => record.id !== id);
        return id;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ deletingItem: false });
      }
    },

    async reorder({ pipelineId, positionsHash }) {
      await SalesStagesAPI.reorder(pipelineId, positionsHash);
      Object.entries(positionsHash).forEach(([id, position]) => {
        const record = this.records.find(r => r.id === Number(id));
        if (record) record.position = position;
      });
    },
  }),
});
