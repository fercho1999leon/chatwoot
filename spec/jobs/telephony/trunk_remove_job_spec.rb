require 'rails_helper'

RSpec.describe Telephony::TrunkRemoveJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Telephony::ControllerClient, delete_trunk: { 'ok' => true }) }

  before do
    allow(Telephony::ControllerClient).to receive_messages(new: client, configured?: true)
    allow(Telephony::TrunkSyncJob).to receive(:perform_later)
  end

  it 'retires the trunk of an account without a telephony inbox' do
    described_class.perform_now(account.id)

    expect(client).to have_received(:delete_trunk).with(account_id: account.id)
  end

  it 'does nothing when the account already has a new telephony inbox (its sync sends the current trunk)' do
    create(:channel_telephony, account: account)

    described_class.perform_now(account.id)

    expect(client).not_to have_received(:delete_trunk)
  end
end
