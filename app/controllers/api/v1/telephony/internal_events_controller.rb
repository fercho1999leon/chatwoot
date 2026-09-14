# Callback del telephony-controller (HMAC-SHA256 + timestamp). Sin sesión de usuario.
class Api::V1::Telephony::InternalEventsController < ActionController::API
  include TelephonySignedRequest

  def create
    payload = JSON.parse(request.raw_post)
    account = Account.find_by(id: payload['account_id'])
    return render json: { applied: false }, status: :ok unless account

    applied = Telephony::EventApplier.new(account: account).apply_event(payload)
    render json: { applied: applied }
  rescue JSON::ParserError
    head :unprocessable_entity
  end
end
