require 'rails_helper'

RSpec.describe Telephony::CapabilityResolver do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, phone_number: '+593987654321') }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  # A fresh instance each time: the account caches its has_one :telephony_pbx.
  let(:resolver) { described_class.new(account: account.reload, user: agent, conversation: conversation) }

  before do
    allow(Telephony::ControllerClient).to receive(:configured?).and_return(true)
    account.enable_features!('telephony_calls')
  end

  def resolve
    described_class.new(account: account.reload, user: agent, conversation: conversation).resolve
  end

  it 'reports the first blocker, in order' do
    expect(resolve).to include(enabled: false, can_call: false, reason: 'no_pbx')

    create(:telephony_pbx, account: account)
    expect(resolve[:reason]).to eq('no_trunk')

    create(:channel_telephony, account: account)
    expect(resolve[:reason]).to eq('no_endpoint')

    create(:telephony_endpoint, account: account, user: agent)
    expect(resolve).to include(enabled: true, can_call: true, reason: nil, destination_masked: '+5939****321')
  end

  it 'blocks when the feature is off for the account' do
    account.disable_features!('telephony_calls')
    create(:telephony_pbx, account: account)

    expect(resolver.resolve).to include(enabled: false, reason: 'feature_disabled')
  end

  context 'when everything is configured' do
    before do
      create(:telephony_pbx, account: account)
      create(:channel_telephony, account: account)
      create(:telephony_endpoint, account: account, user: agent)
    end

    it 'blocks conversations of inboxes not allowed by the trunk' do
      Channel::Telephony.find_by(account: account).update!(allowed_inbox_ids: [inbox.id + 1000])

      expect(resolver.resolve).to include(enabled: false, reason: 'inbox_not_enabled')
    end

    it 'blocks contacts without a phone number' do
      contact.update!(phone_number: nil)

      expect(resolver.resolve).to include(enabled: true, can_call: false, reason: 'no_phone', destination_masked: nil)
    end

    it 'exposes the live call and marks the agent busy, confirming it with the controller' do
      projection = create(:telephony_call_projection, account: account, user: agent, conversation: conversation, state: 'answered',
                                                      state_version: 3)
      snapshot = { 'call_id' => projection.external_call_id, 'state' => 'answered', 'state_version' => 3 }
      client = instance_double(Telephony::ControllerClient, call: snapshot)
      allow(Telephony::ControllerClient).to receive(:new).and_return(client)

      result = resolver.resolve

      expect(result).to include(can_call: false, reason: 'agent_busy')
      expect(result[:active_call][:id]).to eq(projection.external_call_id)
    end

    it 'closes a projection the controller no longer knows (lost callback)' do
      projection = create(:telephony_call_projection, account: account, user: agent, conversation: conversation, state: 'answered')
      client = instance_double(Telephony::ControllerClient)
      allow(client).to receive(:call).and_raise(Telephony::ControllerClient::Error.new(404, 'not_found'))
      allow(Telephony::ControllerClient).to receive(:new).and_return(client)

      expect(resolver.resolve).to include(can_call: true, reason: nil, active_call: nil)
      expect(projection.reload).to have_attributes(state: 'ended', end_reason: 'controller_restart')
    end
  end
end
