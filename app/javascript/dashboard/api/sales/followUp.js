/* global axios */
import ApiClient from '../ApiClient';

class SalesFollowUpAPI extends ApiClient {
  constructor() {
    super('crm/follow_up', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  updateConfig(followUp) {
    return axios.patch(this.url, { follow_up: followUp });
  }

  sync() {
    return axios.post(`${this.url}/sync`);
  }
}

export default new SalesFollowUpAPI();
