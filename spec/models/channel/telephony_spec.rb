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

  describe 'trunk modes' do
    it 'accepts only native and existing, and validates the caller ID' do
      expect(build(:channel_telephony, account: account, trunk_mode: 'custom')).not_to be_valid
      expect(build(:channel_telephony, account: account, caller_id: '+59398765432100000000000')).not_to be_valid
      expect(build(:channel_telephony, account: account, trunk_mode: 'existing', host: '')).to be_valid
    end

    it 'names the native FreePBX trunk and sends the carrier data to the controller' do
      native = build(:channel_telephony, account: account)
      expect(native).to be_configured
      expect(native.pbx_trunk_name).to eq("chatwoot-#{account.id}")
      expect(native.controller_payload).to include(mode: 'native', host: 'sip.carrier.test')
      expect(native.controller_payload.keys).not_to include(:max_call_seconds, :dial_format)
    end

    it 'references an existing FreePBX trunk by its optional name' do
      existing = build(:channel_telephony, account: account, trunk_mode: 'existing', host: '', trunk_name: '')
      expect(existing).to be_configured
      expect(existing.pbx_trunk_name).to be_nil
      existing.trunk_name = 'Claro'
      expect(existing.pbx_trunk_name).to eq('Claro')
      expect(build(:channel_telephony, account: account, host: '')).not_to be_configured
    end
  end

  describe 'removal' do
    it 'asks the controller to retire the trunk when the channel is destroyed' do
      channel = create(:channel_telephony, account: account)

      expect { channel.destroy! }.to have_enqueued_job(Telephony::TrunkRemoveJob).with(account.id)
    end
  end
end
