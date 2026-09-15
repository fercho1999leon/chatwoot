require 'rails_helper'

RSpec.describe 'Telephony Calls API', type: :request do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:client) { instance_double(Telephony::ControllerClient, call: {}) }

  before { allow(Telephony::ControllerClient).to receive(:new).and_return(client) }

  describe 'GET /api/v1/accounts/:account_id/telephony_calls/active' do
    let!(:call) do
      create(:telephony_call_projection, account: account, user: owner, state: 'answered', participants: [agent.id])
    end

    it 'returns the live call the user participates in' do
      get active_api_v1_account_telephony_calls_url(account_id: account.id), headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('id' => call.external_call_id, 'state' => 'answered', 'participants' => [agent.id])
    end

    it 'prefers the call the user owns over one they participate in' do
      own = create(:telephony_call_projection, account: account, user: agent, state: 'ringing')

      get active_api_v1_account_telephony_calls_url(account_id: account.id), headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['id']).to eq(own.external_call_id)
    end

    it 'returns the internal call addressed to the user and ignores ended ones' do
      call.update!(state: 'ended', end_reason: 'completed')
      internal = create(:telephony_call_projection, account: account, user: owner, to_user: agent, direction: 'internal',
                                                    conversation: nil, state: 'ringing')

      get active_api_v1_account_telephony_calls_url(account_id: account.id), headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['id']).to eq(internal.external_call_id)
    end

    it 'returns null when the user has no live call' do
      get active_api_v1_account_telephony_calls_url(account_id: account.id), headers: owner.create_new_auth_token, as: :json
      expect(response.parsed_body['id']).to eq(call.external_call_id)

      call.update!(state: 'ended')
      get active_api_v1_account_telephony_calls_url(account_id: account.id), headers: owner.create_new_auth_token, as: :json
      expect(response.body).to eq('null')
    end
  end

  describe 'per-action authorization' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:previous_owner) { create(:user, account: account, role: :agent) }

    def snapshot(call, **overrides)
      { 'call_id' => call.external_call_id, 'state' => call.state, 'state_version' => call.state_version + 1,
        'user_id' => call.user_id, 'ringing_user_ids' => call.ringing_user_ids, 'participants' => call.participants }.merge(overrides)
    end

    def act(action, call, user, **params)
      post public_send(:"#{action}_api_v1_account_telephony_call_url", account_id: account.id, id: call.external_call_id),
           params: params, headers: user.create_new_auth_token, as: :json
    end

    context 'when the agent was only ringing' do
      let(:call) { create(:telephony_call_projection, account: account, user: nil, state: 'ringing', ringing_user_ids: [agent.id]) }

      before do
        allow(client).to receive(:ring_me).and_return(snapshot(call))
        allow(client).to receive(:hangup)
        allow(client).to receive(:hold)
      end

      it 'can still see the call' do
        get api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id), headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:ok)
      end

      it 'cannot hang up or hold' do
        act(:hangup, call, agent)
        expect(response).to have_http_status(:unauthorized)
        act(:hold, call, agent)
        expect(response).to have_http_status(:unauthorized)
        expect(client).not_to have_received(:hangup)
        expect(client).not_to have_received(:hold)
      end

      it 'can ask to be rung again' do
        act(:answer, call, agent)
        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:ring_me).with(call.external_call_id, user_id: agent.id)
      end
    end

    context 'when the agent is the previous owner' do
      let(:call) do
        create(:telephony_call_projection, account: account, user: owner, state: 'answered', previous_user_id: previous_owner.id,
                                           transfer_state: 'completed')
      end

      before { allow(client).to receive(:transfer) }

      it 'cannot transfer the call again' do
        act(:transfer, call, previous_owner, to_user_id: agent.id)
        expect(response).to have_http_status(:unauthorized)
        expect(client).not_to have_received(:transfer)
      end
    end

    context 'when the agent is a conference participant' do
      let(:call) { create(:telephony_call_projection, account: account, user: owner, state: 'answered', participants: [agent.id]) }

      before do
        allow(client).to receive(:hangup).and_return(snapshot(call, 'state' => 'ended', 'end_reason' => 'completed'))
        allow(client).to receive(:leave).and_return(snapshot(call, 'participants' => []))
      end

      it 'can leave the conference' do
        act(:leave, call, agent)
        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:leave).with(call.external_call_id, user_id: agent.id)
      end

      it 'can hang up' do
        act(:hangup, call, agent)
        expect(response).to have_http_status(:ok)
        expect(client).to have_received(:hangup).with(call.external_call_id, requested_by_user_id: agent.id)
        expect(response.parsed_body['state']).to eq('ended')
      end
    end

    context 'when the user is an administrator that never touched the call' do
      let(:call) { create(:telephony_call_projection, account: account, user: owner, state: 'answered') }

      before do
        allow(client).to receive(:hangup).and_return(snapshot(call, 'state' => 'ended', 'end_reason' => 'completed'))
        allow(client).to receive(:hold).and_return(snapshot(call, 'on_hold' => true))
        allow(client).to receive(:ring_me).and_return(snapshot(call))
      end

      it 'can hold, re-ring, purge the recording and hang up' do
        act(:hold, call, admin)
        expect(response).to have_http_status(:ok)
        act(:answer, call, admin)
        expect(response).to have_http_status(:ok)
        delete recording_api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id),
               headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:no_content)
        act(:hangup, call, admin)
        expect(response).to have_http_status(:ok)
      end

      it 'keeps the recording purge away from a mere participant' do
        call.update!(participants: [agent.id])
        delete recording_api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id),
               headers: agent.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/telephony_calls/:id/join' do
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:call) { create(:telephony_call_projection, account: account, user: owner, conversation: conversation, state: 'answered') }

    it 'refuses a target without a linked extension before calling the controller' do
      post join_api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id),
           params: { user_id: agent.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('no_endpoint')
    end

    it 'refuses a target that cannot see the conversation' do
      create(:telephony_endpoint, account: account, user: agent, endpoint: '1002')

      post join_api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id),
           params: { user_id: agent.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('not_inbox_member')
    end

    it 'delegates to the controller once the target is reachable' do
      create(:telephony_endpoint, account: account, user: agent, endpoint: '1002')
      create(:inbox_member, inbox: inbox, user: agent)
      allow(client).to receive(:join).and_return({ 'call_id' => call.external_call_id, 'state' => 'answered', 'state_version' => 2,
                                                   'participants' => [agent.id] })

      post join_api_v1_account_telephony_call_url(account_id: account.id, id: call.external_call_id),
           params: { user_id: agent.id }, headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:join).with(call.external_call_id, user_id: agent.id)
      expect(response.parsed_body['participants']).to eq([agent.id])
    end
  end
end
