/* global axios */
import ApiClient from '../ApiClient';

class UpSalesCalendarEventsAPI extends ApiClient {
  constructor() {
    super('up_sales/calendar_events', { accountScoped: true });
  }

  create(event) {
    return axios.post(this.url, { event });
  }
}

export default new UpSalesCalendarEventsAPI();
