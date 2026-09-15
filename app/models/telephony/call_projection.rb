# == Schema Information
#
# Table name: telephony_call_projections
#
#  id                  :bigint           not null, primary key
#  answered_at         :datetime
#  answered_by         :string
#  contact_name        :string
#  destination_e164    :string           not null
#  did                 :string
#  direction           :string           default("outbound"), not null
#  duration_seconds    :integer
#  end_reason          :string
#  ended_at            :datetime
#  hint                :string
#  on_hold             :boolean          default(FALSE), not null
#  participants        :jsonb            not null
#  peer_on_hold        :boolean          default(FALSE), not null
#  recording_name      :string
#  recording_state     :string
#  requested_at        :datetime
#  ringing_user_ids    :jsonb            not null
#  routed_by           :string
#  state               :string           default("requested"), not null
#  state_version       :integer          default(0), not null
#  transfer_state      :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  conversation_id     :bigint
#  external_call_id    :uuid             not null
#  inbox_id            :bigint
#  last_event_id       :uuid
#  message_id          :bigint
#  previous_user_id    :integer
#  to_user_id          :integer
#  transfer_to_user_id :integer
#  user_id             :bigint
#
# Indexes
#
#  idx_on_account_id_external_call_id_4b1d657f68                  (account_id,external_call_id) UNIQUE
#  idx_on_account_id_user_id_state_e4b12003b6                     (account_id,user_id,state)
#  index_telephony_call_projections_on_account_id_and_created_at  (account_id,created_at)
#  index_telephony_call_projections_on_conversation_id            (conversation_id)
#
class Telephony::CallProjection < ApplicationRecord
  self.table_name = 'telephony_call_projections'

  STATES = %w[requested agent_connecting dialing ringing answered ended].freeze

  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :conversation, optional: true
  belongs_to :to_user, class_name: 'User', optional: true
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

  def internal?
    direction == 'internal'
  end

  # Usuarios que deben recibir los eventos de esta llamada.
  def involved_user_ids
    [user_id, to_user_id, transfer_to_user_id, previous_user_id, *ringing_user_ids, *participants].compact.uniq
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
      from_number: inbound? ? destination_e164 : did, to_number: inbound? ? did : destination_e164, participants: participants,
      recording_url: recording_url, recording_state: recording_state, transcript: nil, previous_user_id: previous_user_id,
      peer_on_hold: peer_on_hold, routed_by: routed_by, hint: hint
    }
  end

  # Enlace firmado y caducable: solo llega a quien pudo leer la tarjeta o el historial (API autenticada).
  RECORDING_URL_TTL = 1.hour

  def recording_url
    return nil unless recording.attached?

    Rails.application.routes.url_helpers.rails_blob_url(recording, expires_in: RECORDING_URL_TTL)
  end

  def destination_masked
    return '***' if destination_e164.length <= 7

    "#{destination_e164[0, 5]}****#{destination_e164[-3..]}"
  end

  PUSH_ATTRIBUTES = %i[state state_version end_reason inbox_id requested_at answered_at ended_at duration_seconds message_id
                       user_id previous_user_id on_hold transfer_to_user_id transfer_state direction did ringing_user_ids
                       answered_by contact_name to_user_id participants peer_on_hold routed_by hint].freeze

  def push_event_data
    PUSH_ATTRIBUTES.index_with { |attr| public_send(attr) }.merge(
      id: external_call_id, conversation_display_id: conversation&.display_id, destination_masked: destination_masked,
      owner_name: user&.available_name, participant_names: User.where(id: participants).map(&:available_name)
    )
  end
end
