FactoryBot.define do
  factory :telephony_pbx, class: 'Telephony::Pbx' do
    account
    ari_url { 'https://pbx.test' }
    ari_user { 'chatwoot' }
    ari_password { 'secret' }
    sip_ws_url { 'wss://pbx.test/ws' }
    sip_domain { 'pbx.test' }
  end
end
