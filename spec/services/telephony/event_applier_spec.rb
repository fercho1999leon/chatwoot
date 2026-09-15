require 'rails_helper'

RSpec.describe Telephony::EventApplier do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:receiver) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
  let!(:projection) do
    create(:telephony_call_projection, account: account, user: agent, conversation: conversation, inbox: inbox,
                                       state: 'requested', state_version: 1)
  end
  let(:applier) { described_class.new(account: account) }
  let(:dispatcher) { Rails.configuration.dispatcher }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:inbox_member, inbox: inbox, user: receiver)
    allow(dispatcher).to receive(:dispatch)
  end

  def event(**overrides)
    { 'event_id' => SecureRandom.uuid, 'call_id' => projection.external_call_id, 'state' => 'answered', 'state_version' => 2,
      'user_id' => agent.id, 'on_hold' => false, 'ringing_user_ids' => [], 'participants' => [] }.merge(overrides.stringify_keys)
  end

  describe '#apply_event' do
    it 'applies a newer version, upserts the call card and broadcasts' do
      expect(applier.apply_event(event(answered_at: Time.current.iso8601))).to be(true)

      projection.reload
      expect(projection.state).to eq('answered')
      expect(projection.state_version).to eq(2)
      expect(projection.message).to have_attributes(content_type: 'voice_call', message_type: 'outgoing')
      expect(projection.message.content_attributes.dig('data', 'status')).to eq('in-progress')
      expect(dispatcher).to have_received(:dispatch).with(Events::Types::TELEPHONY_CALL_UPDATED, anything, hash_including(telephony_call: projection))
    end

    it 'ignores stale versions and duplicate event ids' do
      duplicate = event(state_version: 3)
      expect(applier.apply_event(duplicate)).to be(true)
      expect(applier.apply_event(duplicate)).to be(false)
      expect(applier.apply_event(event(state: 'ringing', state_version: 2))).to be(false)

      expect(projection.reload.state).to eq('answered')
    end

    it 'never resurrects an ended call' do
      applier.apply_event(event(state: 'ended', end_reason: 'completed', state_version: 5))

      expect(applier.apply_event(event(state: 'answered', state_version: 6))).to be(false)
      expect(projection.reload.state).to eq('ended')
    end

    it 'hands the conversation over to the new owner on a completed transfer' do
      applier.apply_event(event(user_id: receiver.id, transfer_state: 'completed', previous_user_id: agent.id, state_version: 4))

      expect(projection.reload.user).to eq(receiver)
      expect(conversation.reload.assignee).to eq(receiver)
      expect(conversation.conversation_participants.pluck(:user_id)).to include(receiver.id)
    end

    it 'tells the agents that were ringing when the call moves on' do
      projection.update!(ringing_user_ids: [receiver.id])

      applier.apply_event(event(state: 'ended', end_reason: 'no_agents', state_version: 3))

      expect(dispatcher).to have_received(:dispatch)
        .with(Events::Types::TELEPHONY_CALL_ENDED, anything, hash_including(previously_ringing: [receiver.id]))
    end

    it 'schedules the recording fetch once the call ended with a recording' do
      expect do
        applier.apply_event(event(state: 'ended', end_reason: 'completed', recording_name: 'call-x', state_version: 3))
      end.to have_enqueued_job(Telephony::RecordingFetchJob).with(projection.id)

      expect(projection.reload).to have_attributes(recording_name: 'call-x', recording_state: 'stored')
    end

    it 'drops events without id or for unknown calls' do
      expect(applier.apply_event(event.except('event_id'))).to be(false)
      expect(applier.apply_event(event(call_id: SecureRandom.uuid))).to be(false)
    end
  end
end
