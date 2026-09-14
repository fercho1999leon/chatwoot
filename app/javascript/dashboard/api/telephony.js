/* global axios */
import ApiClient from './ApiClient';

// Telephony (SIP/WebRTC, CE). Endpoints under /api/v1/accounts/:id/telephony*.
class TelephonyAPI extends ApiClient {
  constructor() {
    super('telephony', { accountScoped: true });
  }

  capabilities(conversationDisplayId) {
    return axios
      .get(`${this.url}/capabilities`, {
        params: { conversation_id: conversationDisplayId },
      })
      .then(r => r.data);
  }

  browserSession() {
    return axios.post(`${this.url}/browser_session`).then(r => r.data);
  }

  createCall(conversationDisplayId, idempotencyKey) {
    return axios
      .post(
        `${this.baseUrl()}/conversations/${conversationDisplayId}/telephony_calls`,
        {},
        { headers: { 'Idempotency-Key': idempotencyKey } }
      )
      .then(r => r.data);
  }

  activeCall() {
    return axios
      .get(`${this.baseUrl()}/telephony_calls/active`)
      .then(r => r.data);
  }

  call(id) {
    return axios
      .get(`${this.baseUrl()}/telephony_calls/${id}`)
      .then(r => r.data);
  }

  hangup(id) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/hangup`)
      .then(r => r.data);
  }

  dtmf(id, digits) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/dtmf`, { digits })
      .then(r => r.data);
  }
}

export default new TelephonyAPI();
