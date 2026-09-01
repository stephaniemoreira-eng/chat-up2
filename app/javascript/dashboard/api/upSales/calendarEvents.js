/* global axios */
import ApiClient from '../ApiClient';

class UpSalesCalendarEventsAPI extends ApiClient {
  constructor() {
    super('up_sales/calendar_events', { accountScoped: true });
  }

  create(event) {
    return axios.post(this.url, { event });
  }

  list({ timeMin, timeMax, maxResults } = {}) {
    return axios.get(this.url, {
      params: { time_min: timeMin, time_max: timeMax, max_results: maxResults },
    });
  }
}

export default new UpSalesCalendarEventsAPI();
