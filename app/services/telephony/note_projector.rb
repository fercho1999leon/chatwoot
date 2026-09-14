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
    result = I18n.t("telephony.end_reason.#{projection.end_reason || 'unknown'}", default: projection.end_reason.to_s)
    duration = projection.duration_seconds ? Time.at(projection.duration_seconds).utc.strftime('%M:%S') : nil
    if projection.inbound?
      answered_by = projection.user&.name || projection.answered_by.presence || I18n.t('telephony.nobody')
      I18n.t('telephony.inbound_note', caller: projection.contact_name.presence || projection.destination_masked, agent: answered_by,
                                       result: result, duration: duration || '00:00', id: projection.external_call_id.to_s[0, 8])
    else
      I18n.t('telephony.note', agent: projection.user.name, destination: projection.destination_masked, result: result,
                               duration: duration || '00:00', id: projection.external_call_id.to_s[0, 8])
    end
  end
end
