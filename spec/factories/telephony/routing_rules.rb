FactoryBot.define do
  factory :telephony_routing_rule, class: 'Telephony::RoutingRule' do
    account
    sequence(:name) { |n| "Rule #{n}" }
    sequence(:position)
    enabled { true }
    conditions { {} }
    destination { { 'type' => 'hangup' } }
  end
end
