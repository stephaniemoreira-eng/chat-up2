import salesStagesAPI from '../stages';
import ApiClient from '../../ApiClient';

describe('#SalesStagesAPI', () => {
  it('creates correct instance', () => {
    expect(salesStagesAPI).toBeInstanceOf(ApiClient);
    expect(salesStagesAPI).toHaveProperty('get');
    expect(salesStagesAPI).toHaveProperty('create');
    expect(salesStagesAPI).toHaveProperty('update');
    expect(salesStagesAPI).toHaveProperty('delete');
    expect(salesStagesAPI).toHaveProperty('reorder');
  });

  describe('API calls', () => {
    const originalAxios = window.axios;
    const axiosMock = {
      post: vi.fn(() => Promise.resolve()),
      get: vi.fn(() => Promise.resolve()),
      patch: vi.fn(() => Promise.resolve()),
      delete: vi.fn(() => Promise.resolve()),
    };

    beforeEach(() => {
      window.axios = axiosMock;
    });

    afterEach(() => {
      window.axios = originalAxios;
    });

    it('#get fetches stages nested under the given pipeline', () => {
      salesStagesAPI.get(1);
      expect(axiosMock.get).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/1/stages'
      );
    });

    it('#create posts to the nested stages endpoint', () => {
      salesStagesAPI.create(1, { name: 'Qualified' });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/1/stages',
        { name: 'Qualified' }
      );
    });

    it('#update patches the nested stage', () => {
      salesStagesAPI.update(1, 2, { name: 'Won' });
      expect(axiosMock.patch).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/1/stages/2',
        { name: 'Won' }
      );
    });

    it('#delete removes the nested stage', () => {
      salesStagesAPI.delete(1, 2);
      expect(axiosMock.delete).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/1/stages/2'
      );
    });

    it('#reorder posts a positions_hash scoped to the pipeline', () => {
      salesStagesAPI.reorder(1, { 2: 0, 3: 1 });
      expect(axiosMock.post).toHaveBeenCalledWith(
        '/api/v1/crm/pipelines/1/stages/reorder',
        { positions_hash: { 2: 0, 3: 1 } }
      );
    });
  });
});
