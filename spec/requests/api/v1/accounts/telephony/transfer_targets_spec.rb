require 'rails_helper'

RSpec.describe 'Telephony transfer targets API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:targets) do
    { 'extensions' => [{ 'number' => '1002', 'name' => 'Luis' }], 'queues' => [{ 'number' => '700', 'name' => 'Soporte' }],
      'ringgroups' => [{ 'number' => '600', 'name' => 'Ventas' }] }
  end
  let(:client) { instance_double(Telephony::ControllerClient, transfer_targets: targets) }

  before { allow(Telephony::ControllerClient).to receive(:new).and_return(client) }

  it 'lists the FreePBX extensions, queues and ring groups for an agent with an extension' do
    create(:telephony_endpoint, account: account, user: agent)

    get "/api/v1/accounts/#{account.id}/telephony/transfer_targets", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(targets)
    expect(client).to have_received(:transfer_targets).with(account_id: account.id)
  end

  it 'refuses agents without an extension' do
    get "/api/v1/accounts/#{account.id}/telephony/transfer_targets", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('no_endpoint')
  end
end
