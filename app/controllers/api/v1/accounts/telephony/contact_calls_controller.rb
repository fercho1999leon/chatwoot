# Llamar a un contacto desde su ficha: localiza (o crea) la conversación y origina la llamada en ella.
class Api::V1::Accounts::Telephony::ContactCallsController < Api::V1::Accounts::Telephony::BaseController
  def create
    contact = Current.account.contacts.find(params.require(:contact_id))
    raise CustomExceptions::Telephony::Invalid, 'no_phone' if contact.phone_number.blank?

    conversation = Telephony::ConversationLocator.new(account: Current.account, contact: contact).find_or_create
    @telephony_call, created = Telephony::CallCreator.new(
      account: Current.account, user: Current.user, conversation: conversation, idempotency_key: request.headers['Idempotency-Key']
    ).perform
    render 'api/v1/accounts/telephony_calls/show', status: created ? :created : :ok
  end
end
