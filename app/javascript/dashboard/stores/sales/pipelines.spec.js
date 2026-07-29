import { setActivePinia, createPinia } from 'pinia';
import SalesPipelinesAPI from 'dashboard/api/sales/pipelines';
import { useSalesPipelinesStore } from './pipelines';

vi.mock('dashboard/api/sales/pipelines', () => ({
  default: {
    get: vi.fn(),
    reorder: vi.fn(),
  },
}));

vi.mock('dashboard/store/utils/api', () => ({
  throwErrorMessage: vi.fn(error => error),
}));

describe('salesPipelines store', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.clearAllMocks();
  });

  it('sorts pipelines by position via getPipelines', async () => {
    SalesPipelinesAPI.get.mockResolvedValueOnce({
      data: {
        payload: [
          { id: 1, name: 'B', position: 1 },
          { id: 2, name: 'A', position: 0 },
        ],
      },
    });

    const store = useSalesPipelinesStore();
    await store.get();

    expect(store.getPipelines.map(p => p.id)).toEqual([2, 1]);
  });

  it('updates local positions after a successful reorder', async () => {
    SalesPipelinesAPI.get.mockResolvedValueOnce({
      data: {
        payload: [
          { id: 1, name: 'A', position: 0 },
          { id: 2, name: 'B', position: 1 },
        ],
      },
    });
    SalesPipelinesAPI.reorder.mockResolvedValueOnce({});

    const store = useSalesPipelinesStore();
    await store.get();
    await store.reorder({ 1: 1, 2: 0 });

    expect(SalesPipelinesAPI.reorder).toHaveBeenCalledWith({ 1: 1, 2: 0 });
    expect(store.getPipelines.map(p => p.id)).toEqual([2, 1]);
  });
});
