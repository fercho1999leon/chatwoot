require 'rails_helper'

RSpec.describe 'Telephony Bot API', type: :request do
  let(:account) { create(:account) }
  let(:pbx) { create(:telephony_pbx, account: account) }
  let!(:token) { pbx.generate_bot_token! }
  let(:headers) { { 'Authorization' => "Bearer #{token}" } }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:offline_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_telephony, account: account).inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+593987654321', email: 'ana@example.com') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:call) do
    create(:telephony_call_projection, account: account, user: nil, conversation: conversation, inbox: inbox, direction: 'inbound',
                                       state: 'answered', state_version: 3, did: '593000000000', destination_e164: '+593987654321',
                                       answered_by: '2000', hint: 'ventas')
  end
  let(:client) do
    instance_double(Telephony::ControllerClient, status: { 'agents' => { '1001' => 'Avail', '1002' => 'Unavail' } },
                                                 ring_groups: [{ 'number' => '600', 'description' => 'Ventas', 'members' => ['1001'] }])
  end

  before do
    create(:telephony_endpoint, account: account, user: agent, endpoint: '1001')
    create(:telephony_endpoint, account: account, user: offline_agent, endpoint: '1002')
    allow(Telephony::ControllerClient).to receive(:new).and_return(client)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id.to_s => 'online' })
  end

  describe 'GET /api/v1/telephony/bot/calls/:id' do
    it 'rejects a missing or unknown token' do
      get api_v1_telephony_bot_call_url(call.external_call_id), as: :json
      expect(response).to have_http_status(:unauthorized)

      get api_v1_telephony_bot_call_url(call.external_call_id), headers: { 'Authorization' => 'Bearer nope' }, as: :json
      expect(response).to have_http_status(:unauthorized)

      pbx.revoke_bot_token!
      get api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the call context of the account that owns the token', :aggregate_failures do
      create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact, content: 'Quiero un plan')
      create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: agent, content: 'Claro')
      team = create(:team, account: account, name: 'ventas')

      get api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['call']).to eq('id' => call.external_call_id, 'direction' => 'inbound', 'state' => 'answered', 'did' => '593000000000',
                                 'caller_e164' => '+593987654321', 'answered_by' => '2000', 'routed_by' => nil)
      expect(body['contact']).to eq('id' => contact.id, 'name' => 'Ana', 'phone_number' => '+593987654321', 'email' => 'ana@example.com')
      expect(body['conversation']).to include('id' => conversation.id, 'display_id' => conversation.display_id,
                                              'inbox' => { 'id' => inbox.id, 'name' => 'Telephony' },
                                              'assignee' => { 'id' => agent.id, 'name' => agent.available_name })
      expect(body['conversation']['url']).to end_with("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
      expect(body['conversation']['last_messages'].pluck('sender', 'content')).to eq([['contact', 'Quiero un plan'], %w[agent Claro]])
      expect(body['agents']).to contain_exactly(
        { 'user_id' => agent.id, 'name' => agent.available_name, 'extension' => '1001', 'registered' => true, 'online' => true },
        { 'user_id' => offline_agent.id, 'name' => offline_agent.available_name, 'extension' => '1002', 'registered' => false, 'online' => false }
      )
      expect(body['teams']).to eq([{ 'id' => team.id, 'name' => 'ventas' }])
      expect(body['ringgroups']).to eq([{ 'number' => '600', 'description' => 'Ventas' }])
    end

    it 'hides calls of other accounts' do
      other = create(:telephony_call_projection, account: create(:account))

      get api_v1_telephony_bot_call_url(other.external_call_id), headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('not_found')
    end
  end

  describe 'POST /api/v1/telephony/bot/calls/:id/route' do
    let(:team) { create(:team, account: account) }
    let(:steps) { [{ type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 30 }] }
    let(:snapshot) do
      { 'call_id' => call.external_call_id, 'state' => 'agent_connecting', 'state_version' => 4, 'routed_by' => 'bot',
        'ringing_user_ids' => [agent.id], 'answered_by' => nil }
    end

    before do
      create(:team_member, team: team, user: agent)
      create(:team_member, team: team, user: offline_agent)
      allow(client).to receive(:reroute).and_return(snapshot)
    end

    it 'reroutes to the online team members and leaves the note as a private message' do
      post route_api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json,
                                                                       params: { target: { type: 'team', team_id: team.id }, timeout: 30,
                                                                                 note: 'Cliente quiere un plan de fibra' }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ok' => true, 'steps' => JSON.parse(steps.to_json))
      expect(client).to have_received(:reroute).with(call.external_call_id, steps: steps, by: 'bot', note: 'Cliente quiere un plan de fibra')
      expect(call.reload).to have_attributes(state: 'agent_connecting', routed_by: 'bot', ringing_user_ids: [agent.id])
      note = conversation.messages.last
      expect(note).to have_attributes(private: true, content: 'Cliente quiere un plan de fibra', message_type: 'outgoing', sender: nil)
    end

    it 'routes to a ring group without leaving a note when none is given' do
      expect do
        post route_api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json,
                                                                         params: { target: { type: 'ringgroup', number: '600' } }
      end.not_to change(conversation.messages.where(private: true), :count)

      expect(response).to have_http_status(:ok)
      expect(client).to have_received(:reroute)
        .with(call.external_call_id, steps: [{ type: 'ringgroup', number: '600', timeout: 20, expand: true }], by: 'bot', note: nil)
    end

    it 'maps controller refusals to 409' do
      allow(client).to receive(:reroute).and_raise(Telephony::ControllerClient::Error.new(409, 'not_reroutable'))

      post route_api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json,
                                                                       params: { target: { type: 'hangup' } }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('not_reroutable')
    end

    it 'answers 422 when nobody eligible is online or the target is invalid' do
      post route_api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json,
                                                                       params: { target: { type: 'agents', user_ids: [offline_agent.id] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_agents_online')

      post route_api_v1_telephony_bot_call_url(call.external_call_id), headers: headers, as: :json,
                                                                       params: { target: { type: 'ivr', ivr_id: '1' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_target')
      expect(client).not_to have_received(:reroute)
    end

    it 'rejects a missing token' do
      post route_api_v1_telephony_bot_call_url(call.external_call_id), params: { target: { type: 'hangup' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(client).not_to have_received(:reroute)
    end
  end
end
