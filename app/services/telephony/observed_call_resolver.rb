# Llamada que enruta FreePBX y el telephony-controller observa (modelo «Asterisk enruta, Chatwoot atiende»):
# FreePBX ya decidió a quién suena, así que aquí no hay plan. El DID decide el inbox de la conversación:
# el número de un inbox de WhatsApp → ese inbox; cualquier otro (DIDs del carrier) → el inbox de Telefonía.
class Telephony::ObservedCallResolver
  pattr_initialize [:account!, :call_id!, :caller_e164!, :did!]

  def resolve
    raise CustomExceptions::Telephony::Invalid, 'no_telephony_inbox' unless inbox

    conversation = find_or_create_conversation
    projection = create_projection(conversation)
    {
      conversation_id: conversation.id, conversation_display_id: conversation.display_id, inbox_id: conversation.inbox_id,
      contact_id: contact.id, contact_name: contact.name.presence, projection_id: projection.id
    }
  end

  def inbox
    @inbox ||= whatsapp_inbox || Channel::Telephony.where(account_id: account.id).order(:id).first&.inbox
  end

  private

  def whatsapp_inbox
    key = Telephony::Did.key(did)
    account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).find do |candidate|
      Telephony::Did.key(candidate.channel.phone_number) == key
    end
  end

  def contact
    @contact ||= account.contacts.find_by(phone_number: caller_e164) || contact_inbox.contact
  end

  # WhatsApp identifica al contacto por su número sin '+'; Telefonía por el E.164.
  def source_id
    inbox.whatsapp? ? caller_e164.delete('+') : caller_e164
  end

  def contact_inbox
    @contact_inbox ||= ContactInboxWithContactBuilder.new(
      inbox: inbox, source_id: source_id, contact_attributes: { phone_number: caller_e164, name: caller_e164 }
    ).perform
  end

  # Conversación abierta más reciente del contacto en el inbox del DID; si no hay, una nueva en ese inbox.
  def find_or_create_conversation
    existing = contact.conversations.where(inbox: inbox, status: :open).order(last_activity_at: :desc).first
    return existing if existing

    target = contact.contact_inboxes.find_by(inbox: inbox) ||
             ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: source_id).perform
    ConversationBuilder.new(params: {}, contact_inbox: target).perform
  end

  def create_projection(conversation)
    Telephony::CallProjection.create!(
      account: account, external_call_id: call_id, user: nil, conversation: conversation, inbox_id: conversation.inbox_id,
      state: 'requested', state_version: 0, destination_e164: caller_e164, direction: 'inbound', did: did,
      contact_name: contact.name.presence, requested_at: Time.current, source: 'pbx'
    )
  end
end
