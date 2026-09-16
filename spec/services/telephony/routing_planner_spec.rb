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

  def plan(did: '593000000000', caller: '+593987654321', known: contact, hint: nil)
    described_class.new(account: account, conversation: conversation, contact: known, did: did, caller_e164: caller,
                        telephony_inbox: telephony_inbox, hint: hint).plan
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

  it 'carries the bot decision limit (max_seconds) of an extension rule and rejects it elsewhere' do
    create(:telephony_routing_rule, account: account, position: 1,
                                    destination: { 'type' => 'extension', 'extension' => '2000', 'max_seconds' => '45' })

    expect(plan.first).to eq(type: 'extension', extension: '2000', timeout: 20, max_seconds: 45)
    expect(build(:telephony_routing_rule, account: account,
                                          destination: { 'type' => 'extension', 'extension' => '2000', 'max_seconds' => '3' })).not_to be_valid
    expect(build(:telephony_routing_rule, account: account,
                                          destination: { 'type' => 'ringgroup', 'number' => '600', 'max_seconds' => '45' })).not_to be_valid
    expect(build(:telephony_routing_rule, account: account,
                                          destination: { 'type' => 'extension', 'extension' => '2000', 'max_seconds' => '' })).to be_valid
  end

  it 'evaluates the rules by position, not by insertion order' do
    create(:telephony_routing_rule, account: account, position: 2, destination: { 'type' => 'extension', 'extension' => '2000' })
    create(:telephony_routing_rule, account: account, position: 1, destination: { 'type' => 'extension', 'extension' => '1000' })

    expect(plan.map { |s| s[:extension] }).to eq(['1000', '2000', nil])
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

  it 'matches the dialplan hint exactly and treats a blank hint condition as any' do
    create(:telephony_routing_rule, account: account, position: 1, conditions: { 'hint' => 'ventas' },
                                    destination: { 'type' => 'extension', 'extension' => '2000' })
    create(:telephony_routing_rule, account: account, position: 2, conditions: { 'hint' => '' },
                                    destination: { 'type' => 'voicemail', 'extension' => '1001' })

    expect(plan(hint: 'ventas').first).to eq({ type: 'extension', extension: '2000', timeout: 20 })
    expect(plan(hint: 'soporte')).to eq([{ type: 'voicemail', extension: '1001' }])
    expect(plan).to eq([{ type: 'voicemail', extension: '1001' }])
  end

  it 'expands ring groups by default and honours expand: false' do
    create(:telephony_routing_rule, account: account, position: 1, destination: { 'type' => 'ringgroup', 'number' => '600' })
    create(:telephony_routing_rule, account: account, position: 2, destination: { 'type' => 'ringgroup', 'number' => '601', 'expand' => false })
    create(:telephony_routing_rule, account: account, position: 3, destination: { 'type' => 'ringgroup', 'number' => '602', 'expand' => 'true' })

    expect(plan.first(3)).to eq([
                                  { type: 'ringgroup', number: '600', timeout: 20, expand: true },
                                  { type: 'ringgroup', number: '601', timeout: 20, expand: false },
                                  { type: 'ringgroup', number: '602', timeout: 20, expand: true }
                                ])
  end

  describe '#steps_for_target' do
    let(:planner) do
      described_class.new(account: account, conversation: conversation, contact: contact, did: '593000000000',
                          caller_e164: '+593987654321', telephony_inbox: telephony_inbox)
    end
    let(:team) { create(:team, account: account) }

    before do
      create(:team_member, team: team, user: agent)
      create(:team_member, team: team, user: other)
    end

    it 'rings the online team members with an extension' do
      expect(planner.steps_for_target({ 'type' => 'team', 'team_id' => team.id }, timeout: 30))
        .to eq([{ type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 30 }])
    end

    it 'rings the chosen agents and a single agent' do
      expect(planner.steps_for_target({ 'type' => 'agents', 'user_ids' => [agent.id, other.id] }))
        .to eq([{ type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 20 }])
      expect(planner.steps_for_target({ 'type' => 'agent', 'user_id' => agent.id.to_s }))
        .to eq([{ type: 'agents', agents: [{ user_id: agent.id, extension: '1001' }], timeout: 20 }])
    end

    it 'returns no step when nobody eligible is online' do
      expect(planner.steps_for_target({ 'type' => 'agents', 'user_ids' => [other.id] })).to eq([])
    end

    it 'builds PBX steps and clamps the timeout' do
      expect(planner.steps_for_target({ 'type' => 'ringgroup', 'number' => '600' }, timeout: 500))
        .to eq([{ type: 'ringgroup', number: '600', timeout: 120, expand: true }])
      expect(planner.steps_for_target({ 'type' => 'extension', 'extension' => '2000' }, timeout: 1))
        .to eq([{ type: 'extension', extension: '2000', timeout: 5 }])
      expect(planner.steps_for_target({ 'type' => 'voicemail', 'extension' => '1001' })).to eq([{ type: 'voicemail', extension: '1001' }])
      expect(planner.steps_for_target({ 'type' => 'hangup' })).to eq([{ type: 'hangup' }])
    end

    it 'rejects unknown types and missing fields' do
      expect { planner.steps_for_target({ 'type' => 'ivr', 'ivr_id' => '1' }) }
        .to raise_error(CustomExceptions::Telephony::Invalid, 'invalid_target')
      expect { planner.steps_for_target({ 'type' => 'ringgroup' }) }.to raise_error(CustomExceptions::Telephony::Invalid, 'invalid_target')
      expect { planner.steps_for_target({ 'type' => 'agents', 'user_ids' => [] }) }
        .to raise_error(CustomExceptions::Telephony::Invalid, 'invalid_target')
    end
  end
end
