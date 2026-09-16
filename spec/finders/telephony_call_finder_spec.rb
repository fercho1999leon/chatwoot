require 'rails_helper'

RSpec.describe TelephonyCallFinder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:my_inbox) { create(:inbox, account: account) }
  let(:foreign_inbox) { create(:inbox, account: account) }

  def call(**attrs)
    create(:telephony_call_projection, { account: account, user: other, state: 'ended', end_reason: 'completed', inbox: foreign_inbox }.merge(attrs))
  end

  def ids_for(user, params = {})
    Current.user = user
    Current.account = account
    Current.account_user = user.account_users.find_by(account: account)
    described_class.new(user, account, ActionController::Parameters.new(params)).perform[:calls].map(&:id)
  end

  before { create(:inbox_member, inbox: my_inbox, user: agent) }

  describe 'visibility for a plain agent' do
    it 'includes every call the agent took part in plus the calls of the inboxes they belong to' do
      owned = call(user: agent)
      transferred_away = call(user: other, previous_user_id: agent.id)
      internal_target = call(user: other, to_user_id: agent.id, direction: 'internal', inbox: nil)
      conference = call(user: other, participants: [agent.id])
      rang_unanswered = call(user: nil, end_reason: 'no_answer', ringing_user_ids: [agent.id, other.id])
      inbox_missed = call(user: nil, end_reason: 'no_answer', inbox: my_inbox)
      unrelated = call(user: other)
      unrelated_missed = call(user: nil, end_reason: 'no_answer', inbox: foreign_inbox)

      visible = ids_for(agent)
      expect(visible).to include(owned.id, transferred_away.id, internal_target.id, conference.id, rang_unanswered.id, inbox_missed.id)
      expect(visible).not_to include(unrelated.id, unrelated_missed.id)
    end

    it 'does not leak inbox membership from another account' do
      other_account = create(:account)
      other_inbox = create(:inbox, account: other_account)
      create(:inbox_member, inbox: other_inbox, user: agent)
      foreign = create(:telephony_call_projection, account: other_account, user: nil, inbox: other_inbox, state: 'ended', end_reason: 'completed')

      expect(ids_for(agent)).not_to include(foreign.id)
    end

    it 'shows administrators the whole account' do
      a = call(user: other)
      b = call(user: nil, end_reason: 'no_answer')

      expect(ids_for(admin)).to include(a.id, b.id)
    end
  end

  describe 'filters' do
    it 'supports the internal direction and the failed status' do
      internal = call(direction: 'internal', inbox: nil, user: other, to_user_id: agent.id)
      failed = call(end_reason: 'bridge_failure', inbox: my_inbox)
      completed = call(inbox: my_inbox)

      expect(ids_for(admin, direction: 'internal')).to eq([internal.id])
      expect(ids_for(admin, status: 'failed')).to eq([failed.id])
      expect(ids_for(admin, status: 'completed')).to contain_exactly(internal.id, completed.id)
    end

    it 'filters by agent participation, not only current ownership' do
      owned = call(user: agent, inbox: my_inbox)
      conference = call(user: other, participants: [agent.id], inbox: my_inbox)
      call(user: other, inbox: my_inbox)

      expect(ids_for(admin, agent_id: agent.id)).to contain_exactly(owned.id, conference.id)
    end
  end
end
