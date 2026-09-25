FactoryBot.define do
  factory :channel_telephony, class: 'Channel::Telephony' do
    account
    trunk_mode { 'native' }
    host { 'sip.carrier.test' }
    username { 'user' }
    password { 'secret' }

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account, name: 'Telephony')
    end
  end
end
