require 'rails_helper'

RSpec.describe 'Telephony internal inbound (signed callback from the controller)', type: :request do
  let(:account) { create(:account) }
  let(:secret) { 'hmac-test' }

  before { create(:channel_telephony, account: account) }

  def post_signed(body)
    raw = body.to_json
    ts = Time.now.to_i.to_s
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{raw}")}"
    post '/api/v1/telephony/internal_inbound', params: raw,
                                               headers: { 'CONTENT_TYPE' => 'application/json', 'X-Telephony-Timestamp' => ts,
                                                          'X-Telephony-Signature' => signature }
  end

  it 'registers an observed FreePBX call without asking the routing rules' do
    with_modified_env TELEPHONY_HMAC_SECRET: secret do
      allow(Telephony::RoutingPlanner).to receive(:new)
      post_signed(account_id: account.id, call_id: SecureRandom.uuid, caller_e164: '+593987654321', did: '59322000000',
                  linkedid: '1790000000.10', observed: true)
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('conversation_id', 'inbox_id', 'projection_id')
    expect(response.parsed_body).not_to have_key('plan')
    expect(Telephony::RoutingPlanner).not_to have_received(:new)
  end
end
