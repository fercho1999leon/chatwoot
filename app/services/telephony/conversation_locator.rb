# Conversación en la que registrar una llamada con un contacto: la abierta más reciente
# (en cualquier inbox) o, si no hay, una nueva en el inbox Telephony de la cuenta.
class Telephony::ConversationLocator
  pattr_initialize [:account!, :contact!]

  def find_or_create
    existing = contact.conversations.where(status: :open).order(last_activity_at: :desc).first
    return existing if existing
    raise CustomExceptions::Telephony::Invalid, 'no_telephony_inbox' unless telephony_inbox

    source_id = contact.phone_number.presence || "contact-#{contact.id}"
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: telephony_inbox, source_id: source_id).perform
    ConversationBuilder.new(params: {}, contact_inbox: contact_inbox).perform
  end

  def telephony_inbox
    @telephony_inbox ||= Channel::Telephony.where(account_id: account.id).order(:id).first&.inbox
  end
end
