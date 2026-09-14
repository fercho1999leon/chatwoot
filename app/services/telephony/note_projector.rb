# Nota privada única por llamada, en la conversación. Nunca sale por el canal del cliente
# (Base::SendOnChannelService descarta `private`).
class Telephony::NoteProjector
  pattr_initialize [:projection!]

  def upsert!
    content = build_content
    if projection.message_id && (message = Message.find_by(id: projection.message_id))
      message.update!(content: content, content_attributes: message.content_attributes.merge(data: attributes))
      return message
    end

    message = Messages::MessageBuilder.new(
      projection.user, projection.conversation,
      { content: content, private: true, message_type: 'outgoing', content_type: 'text', content_attributes: { data: attributes } }
    ).perform
    projection.update_column(:message_id, message.id) # rubocop:disable Rails/SkipsModelValidations
    message
  end

  private

  def attributes
    { telephony_call: projection.push_event_data.slice(:id, :state, :end_reason, :answered_at, :ended_at, :duration_seconds) }
  end

  def build_content
    return I18n.t('telephony.inbound_note', caller: caller_label, agent: answered_by_label, **common_values) if projection.inbound?

    I18n.t('telephony.note', agent: projection.user.name, destination: projection.destination_masked, **common_values)
  end

  def common_values
    seconds = projection.duration_seconds
    {
      result: I18n.t("telephony.end_reason.#{projection.end_reason || 'unknown'}", default: projection.end_reason.to_s),
      duration: seconds ? Time.at(seconds).utc.strftime('%M:%S') : '00:00',
      id: projection.external_call_id.to_s[0, 8]
    }
  end

  def caller_label
    projection.contact_name.presence || projection.destination_masked
  end

  def answered_by_label
    projection.user&.name || projection.answered_by.presence || I18n.t('telephony.nobody')
  end
end
