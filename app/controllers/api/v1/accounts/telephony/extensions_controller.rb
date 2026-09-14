# Extensiones y ring groups existentes en FreePBX (vía controlador → provisioner).
class Api::V1::Accounts::Telephony::ExtensionsController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def index
    render json: telephony_client.extensions(account_id: Current.account.id)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def ring_groups
    render json: telephony_client.ring_groups(account_id: Current.account.id)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def ivrs
    render json: telephony_client.ivrs(account_id: Current.account.id)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  private

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
