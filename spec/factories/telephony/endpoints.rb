FactoryBot.define do
  factory :telephony_endpoint, class: 'Telephony::Endpoint' do
    account
    user
    sequence(:endpoint) { |n| (1000 + n).to_s }
    enabled { true }
  end
end
