require 'rails_helper'

RSpec.describe Channel::Telephony do
  let(:account) { create(:account) }

  before { allow(Telephony::TrunkSyncJob).to receive(:perform_later) }

  describe 'one trunk per account' do
    it 'refuses a second telephony channel in the same account' do
      create(:channel_telephony, account: account)
      second = build(:channel_telephony, account: account)

      expect(second).not_to be_valid
      expect(second.errors[:account_id]).to be_present
    end
  end

  describe 'credentials written to pjsip.conf' do
    it 'rejects control characters in username and password' do
      expect(build(:channel_telephony, account: account, password: "x\n[evil]\ntype=endpoint")).not_to be_valid
      expect(build(:channel_telephony, account: account, username: "u\r\nv")).not_to be_valid
      expect(build(:channel_telephony, account: account, password: 'a;b [ok]')).to be_valid
    end
  end

  describe 'DIDs' do
    it 'stores them as digits without duplicates' do
      channel = create(:channel_telephony, account: account, dids: ' +593 22 000 000, 59322000001 ,+59322000000')

      expect(channel.dids).to eq('59322000000, 59322000001')
      expect(channel.did_list).to eq(%w[59322000000 59322000001])
    end

    it 'refuses a DID another account already declares, in any of its written forms' do
      create(:channel_telephony, account: create(:account), dids: '59322000000', default_country: 'EC')

      clash = build(:channel_telephony, account: account, dids: '022000000', default_country: 'EC')
      expect(clash).not_to be_valid
      expect(clash.errors[:dids].first).to include('022000000')
      expect(build(:channel_telephony, account: account, dids: '59322000001')).to be_valid
    end
  end

  describe 'removal' do
    it 'asks the controller to retire the trunk when the channel is destroyed' do
      channel = create(:channel_telephony, account: account)

      expect { channel.destroy! }.to have_enqueued_job(Telephony::TrunkRemoveJob).with(account.id)
    end
  end
end
