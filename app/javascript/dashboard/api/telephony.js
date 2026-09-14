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

  hold(id) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/hold`)
      .then(r => r.data);
  }

  unhold(id) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/unhold`)
      .then(r => r.data);
  }

  transfer(id, toUserId) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/transfer`, {
        to_user_id: toUserId,
      })
      .then(r => r.data);
  }

  cancelTransfer(id) {
    return axios
      .post(`${this.baseUrl()}/telephony_calls/${id}/cancel_transfer`)
      .then(r => r.data);
  }

  agents(conversationId) {
    return axios
      .get(`${this.url}/agents`, {
        params: { conversation_id: conversationId },
      })
      .then(r => r.data);
  }

  pbx() {
    return axios.get(`${this.url}/pbx`).then(r => r.data);
  }

  updatePbx(pbx) {
    return axios.put(`${this.url}/pbx`, { pbx }).then(r => r.data);
  }

  testPbx(pbx) {
    return axios.post(`${this.url}/pbx/test`, { pbx }).then(r => r.data);
  }

  status() {
    return axios.get(`${this.url}/status`).then(r => r.data);
  }

  endpoints() {
    return axios.get(`${this.url}/endpoints`).then(r => r.data);
  }

  assignExtension(userId, extension, rotate = false) {
    return axios
      .put(`${this.url}/endpoints/${userId}`, { extension, rotate })
      .then(r => r.data);
  }

  unassignExtension(userId) {
    return axios.delete(`${this.url}/endpoints/${userId}`);
  }

  extensions() {
    return axios.get(`${this.url}/extensions`).then(r => r.data);
  }

  ringGroups() {
    return axios.get(`${this.url}/extensions/ring_groups`).then(r => r.data);
  }
}

export default new TelephonyAPI();
