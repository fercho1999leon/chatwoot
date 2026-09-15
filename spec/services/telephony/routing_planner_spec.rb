require 'rails_helper'

RSpec.describe Telephony::RoutingPlanner do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:telephony_inbox) { create(:channel_telephony, account: account).inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+593987654321') }
  let(:conversation) { create(:conversation, account: account, inbox: telephony_inbox, contact: contact, assignee: agent) }
  let(:availability) { { agent.id.to_s => 'online' } }

  before do
    create(:telephony_endpoint, account: account, user: agent, endpoint: '1001')
    create(:telephony_endpoint, account: account, user: other, endpoint: '1002')
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(availability)
  end

  def plan(did: '593000000000', caller: '+593987654321', known: contact)
    described_class.new(account: account, conversation: conversation, contact: known, did: did, caller_e164: caller,
                        telephony_inbox: telephony_inbox).plan
  end

  it 'ends with a hangup when the account has no rules' do
    expect(plan).to eq([{ type: 'hangup' }])
  end

  it 'rings the assignee first and then a terminal PBX destination' do
    create(:telephony_routing_rule, account: account, position: 1, destination: { 'type' => 'assignee', 'timeout' => '15' })
    create(:telephony_routing_rule, account: account, position: 2, destination: { 'type' => 'ivr', 'ivr_id' => '3' })
    create(:telephony_routing_rule, account: account, position: 3, destination: { 'type' => 'agent', 'user_id' => other.id })

    expect(plan).to eq([
                         { type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 15 },
                         { type: 'ivr', id: '3' }
                       ])
  end

  it 'skips agents that are offline or without an extension' do
    create(:telephony_routing_rule, account: account, position: 1, destination: { 'type' => 'agent', 'user_id' => other.id })
    create(:telephony_routing_rule, account: account, position: 2, destination: { 'type' => 'voicemail', 'extension' => '1001' })

    expect(plan).to eq([{ type: 'voicemail', extension: '1001' }])
  end

  it 'rings every online team member with an extension in parallel' do
    team = create(:team, account: account)
    create(:team_member, team: team, user: agent)
    create(:team_member, team: team, user: other)
    create(:telephony_routing_rule, account: account, destination: { 'type' => 'team', 'team_id' => team.id, 'timeout' => '30' })

    expect(plan.first).to eq({ type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 30 })
  end

  it 'evaluates contact_known, dids and caller_prefix conditions' do
    create(:telephony_routing_rule, account: account, position: 1, conditions: { 'contact_known' => 'no' },
                                    destination: { 'type' => 'extension', 'extension' => '2000' })
    create(:telephony_routing_rule, account: account, position: 2, conditions: { 'dids' => '593111111111' },
                                    destination: { 'type' => 'extension', 'extension' => '2001' })
    create(:telephony_routing_rule, account: account, position: 3, conditions: { 'caller_prefix' => '+5939' },
                                    destination: { 'type' => 'ringgroup', 'number' => '600' })

    expect(plan.map { |s| s[:type] }).to eq(%w[ringgroup hangup])
    expect(plan(known: nil).first).to eq({ type: 'extension', extension: '2000', timeout: 20 })
    expect(plan(did: '593111111111').first).to eq({ type: 'extension', extension: '2001', timeout: 20 })
  end

  it 'treats the assignee as offline when they have no extension' do
    Telephony::Endpoint.find_by(user: agent).destroy!
    create(:telephony_routing_rule, account: account, conditions: { 'assignee_online' => 'yes' },
                                    destination: { 'type' => 'assignee' })

    expect(plan).to eq([{ type: 'hangup' }])
  end

  it 'honours business hours of the telephony inbox' do
    allow(telephony_inbox).to receive(:out_of_office?).and_return(true)
    create(:telephony_routing_rule, account: account, position: 1, conditions: { 'business_hours' => 'in' },
                                    destination: { 'type' => 'assignee' })
    create(:telephony_routing_rule, account: account, position: 2, conditions: { 'business_hours' => 'out' },
                                    destination: { 'type' => 'voicemail', 'extension' => '1001' })

    expect(plan).to eq([{ type: 'voicemail', extension: '1001' }])
  end

  it 'ignores disabled rules' do
    create(:telephony_routing_rule, account: account, enabled: false, destination: { 'type' => 'assignee' })

    expect(plan).to eq([{ type: 'hangup' }])
  end
end
