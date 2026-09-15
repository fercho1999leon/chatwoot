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

    it 'copies the peer hold, routing origin and dialplan hint' do
      applier.apply_event(event(peer_on_hold: true, routed_by: 'bot', hint: 'ventas'))

      expect(projection.reload).to have_attributes(peer_on_hold: true, routed_by: 'bot', hint: 'ventas')
      expect(projection.push_event_data).to include(peer_on_hold: true, routed_by: 'bot', hint: 'ventas')
      expect(projection.call_card_data).to include(peer_on_hold: true, routed_by: 'bot', hint: 'ventas')

      applier.apply_event(event(state_version: 3))
      expect(projection.reload.peer_on_hold).to be(false)
    end

    it 'does not mark the event as processed when applying it fails, so a retry applies it' do
      payload = event
      allow(Telephony::NoteProjector).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')

      expect { applier.apply_event(payload) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(Telephony::ProcessedEvent.exists?(event_id: payload['event_id'])).to be(false)
      expect(projection.reload.state).to eq('requested')
      expect(dispatcher).not_to have_received(:dispatch)

      allow(Telephony::NoteProjector).to receive(:new).and_call_original
      expect(described_class.new(account: account).apply_event(payload)).to be(true)
      expect(Telephony::ProcessedEvent.exists?(event_id: payload['event_id'])).to be(true)
      expect(projection.reload.state).to eq('answered')
    end

    it 'treats an already processed event id as a duplicate without touching the projection' do
      payload = event
      Telephony::ProcessedEvent.create!(event_id: payload['event_id'], created_at: Time.current)

      expect(applier.apply_event(payload)).to be(false)
      expect(projection.reload.state).to eq('requested')
      expect(dispatcher).not_to have_received(:dispatch)
      # La transacción quedó limpia: la sesión sigue usable.
      expect(Telephony::ProcessedEvent.count).to eq(1)
    end

    it 'broadcasts only after the whole event has been persisted' do
      order = []
      allow(dispatcher).to receive(:dispatch) { |name, *| order << :dispatch if name.to_s.start_with?('telephony') }
      allow(Telephony::NoteProjector).to receive(:new).and_wrap_original do |m, *args, **kwargs|
        order << :note
        m.call(*args, **kwargs)
      end

      applier.apply_event(event)

      expect(order).to eq(%i[note dispatch])
    end

    it 'drops events without id or for unknown calls' do
      expect(applier.apply_event(event.except('event_id'))).to be(false)
      expect(applier.apply_event(event(call_id: SecureRandom.uuid))).to be(false)
    end
  end
end
