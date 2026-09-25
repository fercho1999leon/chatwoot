require 'rails_helper'

RSpec.describe Telephony::TrunkSyncJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Telephony::ControllerClient) }
  let(:channel) do
    allow(described_class).to receive(:perform_later)
    create(:channel_telephony, account: account)
  end

  before { allow(Telephony::ControllerClient).to receive_messages(new: client, configured?: true) }

  it 'clears the sync error once the controller accepts the trunk (the PBX result comes from GET status)' do
    channel.update_columns(provision_error: 'did_taken') # rubocop:disable Rails/SkipsModelValidations
    allow(client).to receive(:upsert_trunk).and_return({ 'provision' => { 'ok' => true, 'pending' => true } })

    described_class.perform_now(channel.id)

    expect(client).to have_received(:upsert_trunk).with(hash_including(account_id: account.id, dial_format: 'e164'))
    expect(channel.reload.provision_error).to be_nil
  end

  it 'keeps the reason when the controller rejects the trunk' do
    allow(client).to receive(:upsert_trunk).and_raise(Telephony::ControllerClient::Error.new(409, 'did_taken'))

    described_class.perform_now(channel.id)

    expect(channel.reload.provision_error).to eq('did_taken')
  end
end
