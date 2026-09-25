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

  describe 'dial policy' do
    it 'validates the dial format, prefix, allowed destinations and caller ID' do
      expect(build(:channel_telephony, account: account, dial_format: 'weird')).not_to be_valid
      expect(build(:channel_telephony, account: account, dial_prefix: '9x')).not_to be_valid
      expect(build(:channel_telephony, account: account, allowed_prefixes: '593; drop')).not_to be_valid
      expect(build(:channel_telephony, account: account, caller_id: '+59398765432100000000000')).not_to be_valid
      expect(build(:channel_telephony, account: account, dial_format: 'national', dial_prefix: '*77', allowed_prefixes: '593, 1')).to be_valid
    end

    it 'derives the allowed destinations from the default country and sends them to the controller' do
      channel = build(:channel_telephony, account: account, default_country: 'EC', dial_format: 'national', dial_prefix: '9')
      expect(channel.destination_prefixes).to eq(['593'])
      expect(channel.destination_allowed?('+593987654321')).to be(true)
      expect(channel.destination_allowed?('+15551714097')).to be(false)
      expect(channel.controller_payload).to include(dial_format: 'national', dial_prefix: '9', allowed_prefixes: ['593'])
      expect(channel.controller_payload).not_to have_key(:max_call_seconds)

      channel.allowed_prefixes = '*'
      expect(channel.destination_allowed?('+15551714097')).to be(true)
      channel.assign_attributes(allowed_prefixes: '', default_country: '')
      expect(channel.destination_allowed?('+15551714097')).to be(true) # sin país: como antes, cualquiera
    end
  end

  describe 'removal' do
    it 'asks the controller to retire the trunk when the channel is destroyed' do
      channel = create(:channel_telephony, account: account)

      expect { channel.destroy! }.to have_enqueued_job(Telephony::TrunkRemoveJob).with(account.id)
    end
  end
end
