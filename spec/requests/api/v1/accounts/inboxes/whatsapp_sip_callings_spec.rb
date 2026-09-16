require 'rails_helper'

RSpec.describe 'WhatsApp SIP calling API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'sip_calling' => { 'enabled' => true, 'hostname' => 'pbx.test' } })
  end
  let(:inbox) { channel.inbox }
  let(:phone_number_id) { channel.provider_config['phone_number_id'] } # the factory fixes it for whatsapp_cloud
  let(:client) { instance_double(Telephony::ControllerClient) }

  before do
    allow(Telephony::ControllerClient).to receive(:new).and_return(client)
    # Meta's settings endpoint: not under test here.
    stub_request(:get, %r{graph\.facebook\.com/.*/settings}).to_return(status: 200, body: { calling: { status: 'ENABLED' } }.to_json,
                                                                       headers: { 'Content-Type' => 'application/json' })
  end

  describe 'GET /api/v1/accounts/{account_id}/inboxes/{inbox_id}/whatsapp_sip_calling' do
    it 'reports the PBX provisioning state of this number from the controller' do
      allow(client).to receive(:whatsapp_trunks).with(account_id: account.id).and_return(
        'provisioning' => true,
        'trunks' => [{ 'phone_number_id' => phone_number_id, 'name' => "wa-#{phone_number_id}", 'provisioned_at' => '2026-09-15T23:22:14Z',
                       'provision_error' => nil }, { 'phone_number_id' => 'other', 'name' => 'wa-other', 'provision_error' => 'boom' }]
      )

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_sip_calling", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['provision']).to eq('provisioning' => true, 'provisioned_at' => '2026-09-15T23:22:14Z', 'error' => nil,
                                                      'trunk' => "wa-#{phone_number_id}")
      expect(response.parsed_body['config']).to include('enabled' => true)
    end

    it 'degrades to an error field when the controller is unreachable' do
      allow(client).to receive(:whatsapp_trunks).and_raise(Telephony::ControllerClient::Error.new(503, 'controller_unavailable'))

      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_sip_calling", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['provision']).to eq('provisioning' => false, 'error' => 'telephony-controller 503: controller_unavailable')
    end
  end
end
