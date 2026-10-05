require 'rails_helper'

RSpec.describe 'Telephony endpoints API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:bot_user) { create(:user, account: account, role: :agent, name: 'Agente IA') }
  let(:client) { instance_double(Telephony::ControllerClient, upsert_endpoint: { 'ok' => true }) }

  before { allow(Telephony::ControllerClient).to receive(:new).and_return(client) }

  def link(params)
    put "/api/v1/accounts/#{account.id}/telephony/endpoints/#{bot_user.id}", params: params, headers: admin.create_new_auth_token, as: :json
  end

  it 'links with WebRTC by default' do
    link(extension: '1001')

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('extension' => '1001', 'webrtc' => true)
    expect(client).to have_received(:upsert_endpoint)
      .with(account_id: account.id, user_id: bot_user.id, extension: '1001', display_name: 'Agente IA', rotate: false, webrtc: true)
  end

  it 'links an AI voice agent extension without WebRTC and never rotates its secret' do
    link(extension: '2000', webrtc: false, rotate: true)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('extension' => '2000', 'webrtc' => false)
    expect(client).to have_received(:upsert_endpoint).with(hash_including(extension: '2000', webrtc: false, rotate: false))
    expect(Telephony::Endpoint.find_by(account_id: account.id, user_id: bot_user.id)).to have_attributes(endpoint: '2000', webrtc: false)
  end

  it 'lists the webrtc flag' do
    create(:telephony_endpoint, account: account, user: bot_user, endpoint: '2000', webrtc: false)

    get "/api/v1/accounts/#{account.id}/telephony/endpoints", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to contain_exactly(include('user_id' => bot_user.id, 'extension' => '2000', 'webrtc' => false))
  end

  it 'surfaces a missing FreePBX extension as invalid' do
    allow(client).to receive(:upsert_endpoint)
      .and_raise(Telephony::ControllerClient::Error.new(422, 'extension_unavailable'))

    link(extension: '2000', webrtc: false)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Telephony::Endpoint.where(account_id: account.id)).to be_empty
  end
end
