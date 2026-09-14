# Historial de llamadas (página "Calls") alimentado por la telefonía SIP. Sirve GET /calls en CE;
# en Enterprise esa ruta la atiende su CallsController (Twilio/WhatsApp).
class Api::V1::Accounts::TelephonyCallHistoryController < Api::V1::Accounts::BaseController
  def index
    result = TelephonyCallFinder.new(Current.user, Current.account, params).perform
    @calls = result[:calls]
    @calls_count = result[:count]
  end
end
