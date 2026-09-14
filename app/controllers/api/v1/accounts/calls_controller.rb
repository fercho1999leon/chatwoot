# Historial de llamadas (página "Calls"). En CE lo alimenta la telefonía SIP; Enterprise
# trae su propia versión (Twilio/WhatsApp) en enterprise/app/controllers.
class Api::V1::Accounts::CallsController < Api::V1::Accounts::BaseController
  def index
    result = TelephonyCallFinder.new(Current.user, Current.account, params).perform
    @calls = result[:calls]
    @calls_count = result[:count]
  end
end
