# Tarjeta de llamada (mensaje voice_call) única por llamada, en la conversación. Se crea al empezar
# y se actualiza en cada evento; nunca sale por el canal del cliente (Base::SendOnChannelService
# descarta voice_call). El texto es el resumen que se ve en la lista de conversaciones.
class Telephony::NoteProjector
  pattr_initialize [:projection!]

  def upsert!
    content = build_content
    if projection.message_id && (message = Message.find_by(id: projection.message_id))
      message.update!(content: content, content_attributes: message.content_attributes.merge('data' => data_payload))
      return message
    end

    message = create_message(content)
    projection.update_column(:message_id, message.id) # rubocop:disable Rails/SkipsModelValidations
    message
  end

  private

  # Directo (sin MessageBuilder): las entrantes llevan al contacto como remitente y el builder
  # solo admite mensajes "incoming" en inboxes API. voice_call nunca se envía al canal.
  def create_message(content)
    conversation = projection.conversation
    conversation.messages.create!(
      account: projection.account, inbox: conversation.inbox, sender: sender, content: content,
      message_type: projection.inbound? ? 'incoming' : 'outgoing', content_type: 'voice_call',
      content_attributes: { 'data' => data_payload }
    )
  end

  def sender
    projection.inbound? ? projection.conversation.contact : projection.user
  end

  def data_payload
    { 'call_id' => projection.id, 'call_sid' => projection.external_call_id, 'call_source' => 'asterisk',
      'call_direction' => projection.direction, 'status' => projection.display_status }
  end

  def build_content
    return I18n.t('telephony.inbound_note', caller: caller_label, agent: answered_by_label, **common_values) if projection.inbound?

    I18n.t('telephony.note', agent: projection.user&.name, destination: projection.destination_masked, **common_values)
  end

  def common_values
    seconds = projection.duration_seconds
    {
      result: I18n.t("telephony.end_reason.#{projection.end_reason || projection.state}", default: projection.end_reason.to_s),
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
