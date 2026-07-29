/* global axios */
import ApiClient from '../ApiClient';

class SalesPipelinesAPI extends ApiClient {
  constructor() {
    super('crm/pipelines', { accountScoped: true });
  }

  reorder(positionsHash) {
    return axios.post(`${this.url}/reorder`, { positions_hash: positionsHash });
  }
}

export default new SalesPipelinesAPI();
