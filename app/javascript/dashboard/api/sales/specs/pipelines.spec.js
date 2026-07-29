import salesPipelinesAPI from '../pipelines';
import ApiClient from '../../ApiClient';

describe('#SalesPipelinesAPI', () => {
  it('creates correct instance', () => {
    expect(salesPipelinesAPI).toBeInstanceOf(ApiClient);
    expect(salesPipelinesAPI).toHaveProperty('get');
    expect(salesPipelinesAPI).toHaveProperty('create');
    expect(salesPipelinesAPI).toHaveProperty('update');
    expect(salesPipelinesAPI).toHaveProperty('delete');
    expect(salesPipelinesAPI).toHaveProperty('reorder');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('uses the crm/pipelines resource path', () => {
      salesPipelinesAPI.get();
      expect(axiosMock.get).toHaveBeenCalledWith('/api/v1/crm/pipelines');
    });

    it('#reorder posts a positions_hash', () => {
      salesPipelinesAPI.reorder({ 1: 0, 2: 1 });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/reorder',
        { positions_hash: { 1: 0, 2: 1 } }
      );
    });
  });
});
