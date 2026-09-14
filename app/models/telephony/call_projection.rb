class Telephony::CallProjection < ApplicationRecord
  self.table_name = 'telephony_call_projections'

  STATES = %w[requested agent_connecting dialing ringing answered ended].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :conversation
  belongs_to :inbox, optional: true
  belongs_to :message, optional: true

  validates :external_call_id, presence: true, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where.not(state: 'ended') }

  def ended?
    state == 'ended'
  end

  def destination_masked
    return '***' if destination_e164.length <= 7

    "#{destination_e164[0, 5]}****#{destination_e164[-3..]}"
  end

  def push_event_data
    {
      id: external_call_id,
      state: state,
      state_version: state_version,
      end_reason: end_reason,
      conversation_display_id: conversation.display_id,
      inbox_id: inbox_id,
      destination_masked: destination_masked,
      requested_at: requested_at,
      answered_at: answered_at,
      ended_at: ended_at,
      duration_seconds: duration_seconds,
      message_id: message_id,
      user_id: user_id,
      previous_user_id: previous_user_id,
      on_hold: on_hold,
      transfer_to_user_id: transfer_to_user_id,
      transfer_state: transfer_state
    }
  end
end
