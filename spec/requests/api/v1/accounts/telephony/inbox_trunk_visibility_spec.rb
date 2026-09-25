require 'rails_helper'

# El bloque `telephony` del inbox (host, usuario, IPs y DIDs del carrier) solo lo ven administradores.
RSpec.describe 'Telephony inbox JSON visibility', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:channel) do
    allow(Telephony::TrunkSyncJob).to receive(:perform_later)
    create(:channel_telephony, account: account, dids: '59322000000', carrier_ips: ['203.0.113.10'], dial_format: 'national')
  end

  before { create(:inbox_member, inbox: channel.inbox, user: agent) }

  def inbox_json(user)
    get "/api/v1/accounts/#{account.id}/inboxes/#{channel.inbox.id}", headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'shows the trunk to administrators without the password' do
    telephony = inbox_json(admin)['telephony']
    expect(telephony).to include('host' => 'sip.carrier.test', 'dids' => '59322000000', 'dial_format' => 'national', 'password' => '********')
    expect(telephony).not_to have_key('max_call_seconds')
  end

  it 'hides the trunk from agents' do
    expect(inbox_json(agent)).not_to have_key('telephony')
  end
end
