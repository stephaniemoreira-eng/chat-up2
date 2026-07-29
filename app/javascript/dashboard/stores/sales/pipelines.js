import { createStore } from 'dashboard/store/storeFactory';
import SalesPipelinesAPI from 'dashboard/api/sales/pipelines';

export const useSalesPipelinesStore = createStore({
  name: 'salesPipelines',
  type: 'pinia',
  API: SalesPipelinesAPI,
  getters: {
    getPipelines: state =>
      [...state.records].sort((a, b) => a.position - b.position),
  },
  actions: () => ({
    async reorder(positionsHash) {
      await SalesPipelinesAPI.reorder(positionsHash);
      Object.entries(positionsHash).forEach(([id, position]) => {
        const record = this.records.find(r => r.id === Number(id));
        if (record) record.position = position;
      });
    },
  }),
});
