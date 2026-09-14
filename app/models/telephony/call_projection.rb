class Telephony::CallProjection < ApplicationRecord
  self.table_name = 'telephony_call_projections'

  STATES = %w[requested agent_connecting dialing ringing answered ended].freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :conversation
  belongs_to :inbox, optional: true
  belongs_to :message, optional: true, inverse_of: :telephony_call

  has_one_attached :recording

  validates :external_call_id, presence: true, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where.not(state: 'ended') }

  def ended?
    state == 'ended'
  end

  def inbound?
    direction == 'inbound'
  end

  # Estado en el vocabulario de la tarjeta de llamada de Chatwoot (VoiceCall bubble / Calls page).
  def display_status
    return 'ringing' if %w[requested agent_connecting dialing ringing].include?(state)
    return 'in-progress' if state == 'answered'

    case end_reason
    when 'completed', 'max_duration', 'to_ivr', 'to_voicemail' then 'completed'
    when 'no_answer', 'agent_no_answer', 'missed', 'no_agents', 'busy' then 'no-answer'
    when 'rejected', 'canceled', 'agent_hangup' then 'rejected'
    else 'failed'
    end
  end

  # Misma forma que Call#push_event_data (Enterprise) para reutilizar la burbuja y el historial.
  def call_card_data
    {
      id: id, provider_call_id: external_call_id, provider: 'asterisk', direction: direction, status: display_status,
      duration_seconds: duration_seconds, end_reason: end_reason, accepted_by_agent_id: user_id,
      accepted_by_agent_name: user&.available_name, started_at: answered_at&.to_i, ended_at: ended_at,
      from_number: inbound? ? destination_e164 : did, to_number: inbound? ? did : destination_e164,
      recording_url: recording_url, transcript: nil, previous_user_id: previous_user_id
    }
  end

  def recording_url
    return nil unless recording.attached?

    Rails.application.routes.url_helpers.rails_blob_url(recording)
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
