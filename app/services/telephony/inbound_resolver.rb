# Entrante: decide contacto, conversación y plan de timbrado a partir de las reglas de la cuenta.
# Devuelve lo que el telephony-controller necesita para ejecutar el plan.
class Telephony::InboundResolver
  pattr_initialize [:account!, :call_id!, :caller_e164!, :did!]

  def resolve
    conversation = find_or_create_conversation
    projection = create_projection(conversation)
    plan = Telephony::RoutingPlanner.new(account: account, conversation: conversation, contact: contact, did: did,
                                         caller_e164: caller_e164, telephony_inbox: telephony_inbox).plan
    {
      conversation_id: conversation.id, conversation_display_id: conversation.display_id, inbox_id: conversation.inbox_id,
      contact_id: contact&.id, contact_name: contact&.name.presence, plan: plan, projection_id: projection.id
    }
  end

  private

  def telephony_channel
    @telephony_channel ||= Channel::Telephony.where(account_id: account.id).order(:id).first
  end

  def telephony_inbox
    @telephony_inbox ||= telephony_channel&.inbox
  end

  def contact
    return @contact if defined?(@contact)

    @contact = account.contacts.find_by(phone_number: caller_e164)
  end

  # Conversación abierta más reciente del contacto (en cualquier inbox); si no hay, una nueva en el
  # inbox Telephony (creando el contacto si el número es desconocido).
  def find_or_create_conversation
    return Telephony::ConversationLocator.new(account: account, contact: contact).find_or_create if contact
    raise CustomExceptions::Telephony::Invalid, 'no_telephony_inbox' unless telephony_inbox

    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: telephony_inbox, source_id: caller_e164, contact_attributes: { phone_number: caller_e164, name: caller_e164 }
    ).perform
    @contact = contact_inbox.contact
    ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
  end

  def create_projection(conversation)
    Telephony::CallProjection.create!(
      account: account, external_call_id: call_id, user: nil, conversation: conversation, inbox_id: conversation.inbox_id,
      state: 'requested', state_version: 0, destination_e164: caller_e164, direction: 'inbound', did: did,
      contact_name: contact&.name.presence, requested_at: Time.current
    )
  end
end
