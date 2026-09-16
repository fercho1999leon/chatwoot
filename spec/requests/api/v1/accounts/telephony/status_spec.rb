require 'rails_helper'

RSpec.describe 'Telephony status API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:remote) do
    { 'pbx_configured' => true, 'ari_connected' => true, 'agents' => { '1001' => 'Avail' },
      'health' => { 'version' => 'v0.1.9', 'outbox' => { 'pending' => 0, 'oldest_seconds' => 0, 'failing' => 0 },
                    'calls_by_state' => {}, 'legs_live' => 0, 'recordings' => { 'stored' => 1, 'failed' => 0, 'missing' => 0 } } }
  end
  let(:client) { instance_double(Telephony::ControllerClient, status: remote) }

  before do
    allow(Telephony::ControllerClient).to receive(:new).and_return(client)
    create(:telephony_pbx, account: account)
  end

  describe 'GET /api/v1/accounts/:id/telephony/status' do
    it 'passes the controller health through and adds the recordings Chatwoot still owes' do
      ended = { account: account, user: admin, state: 'ended', recording_name: 'x' }
      create(:telephony_call_projection, **ended, ended_at: 1.hour.ago, recording_state: 'stored')
      create(:telephony_call_projection, **ended, ended_at: 1.hour.ago, recording_state: 'failed')
      create(:telephony_call_projection, **ended, ended_at: 9.days.ago, recording_state: 'failed')

      get "/api/v1/accounts/#{account.id}/telephony/status", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['health']).to include('version' => 'v0.1.9')
      expect(body['recordings']).to eq('pending' => 1, 'failed' => 1, 'missing' => 0)
    end

    it 'still reports local recordings when the controller is down' do
      allow(client).to receive(:status).and_raise(Telephony::ControllerClient::Error.new(503, 'pbx_unreachable'))

      get "/api/v1/accounts/#{account.id}/telephony/status", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body).to include('ari_connected' => false, 'error' => 'pbx_unreachable',
                                              'recordings' => { 'pending' => 0, 'failed' => 0, 'missing' => 0 })
    end

    it 'is admin only' do
      get "/api/v1/accounts/#{account.id}/telephony/status", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/accounts/:id/telephony/pbx/retry_recordings' do
    it 'enqueues the sweep for the account' do
      expect do
        post "/api/v1/accounts/#{account.id}/telephony/pbx/retry_recordings", headers: admin.create_new_auth_token, as: :json
      end.to have_enqueued_job(Telephony::RecordingSweepJob).with(account_id: account.id)
      expect(response).to have_http_status(:accepted)
    end
  end
end
