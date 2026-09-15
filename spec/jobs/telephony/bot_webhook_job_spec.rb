require 'rails_helper'

RSpec.describe Telephony::BotWebhookJob do
  let(:account) { create(:account) }
  let(:pbx) { create(:telephony_pbx, account: account, bot_webhook_url: 'https://n8n.test/webhook/calls') }
  let(:inbox) { create(:channel_telephony, account: account).inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+593987654321') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:projection) do
    create(:telephony_call_projection, account: account, user: nil, conversation: conversation, inbox: inbox, direction: 'inbound',
                                       did: '593000000000', destination_e164: '+593987654321', hint: 'ventas')
  end

  before do
    pbx.generate_bot_token!
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  it 'posts the inbound context signed with the bot token digest' do
    request = stub_request(:post, 'https://n8n.test/webhook/calls').to_return(status: 200)

    described_class.perform_now(projection.id)

    expect(request).to have_been_requested
    expect(request.with do |req|
      body = JSON.parse(req.body)
      signature = OpenSSL::HMAC.hexdigest('SHA256', pbx.reload.bot_token_digest, req.body)
      expect(body).to include('event' => 'call.inbound', 'call_id' => projection.external_call_id, 'account_id' => account.id,
                              'caller_e164' => '+593987654321', 'did' => '593000000000', 'hint' => 'ventas')
      expect(body['contact']).to include('id' => contact.id, 'name' => 'Ana')
      expect(body['conversation']).to include('id' => conversation.id, 'display_id' => conversation.display_id)
      expect(body['api']['route_url']).to end_with("/api/v1/telephony/bot/calls/#{projection.external_call_id}/route")
      expect(req.headers['X-Chatwoot-Telephony-Signature']).to eq(signature)
      true
    end).to have_been_requested
  end

  it 'does nothing without a webhook URL and swallows delivery failures' do
    pbx.update!(bot_webhook_url: '')
    expect { described_class.perform_now(projection.id) }.not_to raise_error

    pbx.update!(bot_webhook_url: 'https://n8n.test/webhook/calls')
    stub_request(:post, 'https://n8n.test/webhook/calls').to_timeout
    expect { described_class.perform_now(projection.id) }.not_to raise_error
  end
end
