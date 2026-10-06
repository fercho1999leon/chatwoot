# Llamar a un contacto desde su ficha, o a un número desde el marcador de la página de llamadas: localiza
# (o crea) el contacto y la conversación, y origina la llamada en ella.
class Api::V1::Accounts::Telephony::ContactCallsController < Api::V1::Accounts::Telephony::BaseController
  def create
    contact = params[:phone_number].present? ? contact_for_number : Current.account.contacts.find(params.require(:contact_id))
    raise CustomExceptions::Telephony::Invalid, 'no_phone' if contact.phone_number.blank?

    conversation = Telephony::ConversationLocator.new(account: Current.account, contact: contact).find_or_create
    @telephony_call, created = Telephony::CallCreator.new(
      account: Current.account, user: Current.user, conversation: conversation, idempotency_key: request.headers['Idempotency-Key']
    ).perform
    render 'api/v1/accounts/telephony_calls/show', status: created ? :created : :ok
  end

  private

  # Número nacional (09…, 02…) según el país por defecto de la troncal, o internacional (+…, 00…).
  def contact_for_number
    default_country = Channel::Telephony.where(account_id: Current.account.id).order(:id).first&.default_country
    e164 = Telephony::Did.e164(params[:phone_number], default_country)
    raise CustomExceptions::Telephony::Invalid, 'invalid_phone' unless e164

    Current.account.contacts.find_by(phone_number: e164) ||
      Current.account.contacts.create!(name: e164, phone_number: e164)
  end
end
