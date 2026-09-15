FactoryBot.define do
  factory :telephony_call_projection, class: 'Telephony::CallProjection' do
    account
    user
    conversation
    external_call_id { SecureRandom.uuid }
    state { 'requested' }
    state_version { 0 }
    direction { 'outbound' }
    destination_e164 { '+593999999999' }
    requested_at { Time.current }
  end
end
