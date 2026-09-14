# Credenciales SIP/ICE del propio usuario. Solo por HTTP autenticado, nunca por ActionCable.
class Api::V1::Accounts::Telephony::BrowserSessionsController < Api::V1::Accounts::Telephony::BaseController
  def create
    raise CustomExceptions::Telephony::Invalid, 'feature_disabled' unless Current.account.feature_enabled?('telephony_calls')
    raise CustomExceptions::Telephony::Invalid, 'no_endpoint' unless Telephony::Endpoint.exists?(account_id: Current.account.id,
                                                                                                    user_id: Current.user.id, enabled: true)

    session = telephony_client.browser_session(account_id: Current.account.id, user_id: Current.user.id)
    response.headers['Cache-Control'] = 'no-store'
    render json: session
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end
end
