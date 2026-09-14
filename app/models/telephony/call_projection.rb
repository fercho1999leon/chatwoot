class Telephony::CallProjection < ApplicationRecord
  self.table_name = 'telephony_call_projections'

  STATES = %w[requested agent_connecting dialing ringing answered ended].freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :conversation
  belongs_to :inbox, optional: true
  belongs_to :message, optional: true

  validates :external_call_id, presence: true, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where.not(state: 'ended') }

  def ended?
    state == 'ended'
  end

  def inbound?
    direction == 'inbound'
  end

  def destination_masked
    return '***' if destination_e164.length <= 7

    "#{destination_e164[0, 5]}****#{destination_e164[-3..]}"
  end

  PUSH_ATTRIBUTES = %i[state state_version end_reason inbox_id requested_at answered_at ended_at duration_seconds message_id
                       user_id previous_user_id on_hold transfer_to_user_id transfer_state direction did ringing_user_ids
                       answered_by contact_name].freeze

  def push_event_data
    PUSH_ATTRIBUTES.index_with { |attr| public_send(attr) }.merge(
      id: external_call_id, conversation_display_id: conversation.display_id, destination_masked: destination_masked
    )
  end
end
