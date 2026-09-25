# Entrante: el controlador pregunta a quién timbrar (destino «Chatwoot» de FreePBX) o, con `observed`, da de alta
# una llamada que enruta FreePBX y él solo observa. Firmado (HMAC), sin sesión de usuario.
class Api::V1::Telephony::InternalInboundController < ActionController::API
  include TelephonySignedRequest

  def create
    payload = JSON.parse(request.raw_post)
    account = Account.find_by(id: payload['account_id'])
    return render json: { error: 'unknown_account' }, status: :not_found unless account

    render json: resolver(account, payload).resolve
  rescue JSON::ParserError
    head :unprocessable_entity
  rescue CustomExceptions::Telephony::Invalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def resolver(account, payload)
    args = { account: account, call_id: payload['call_id'], caller_e164: payload['caller_e164'].to_s, did: payload['did'].to_s }
    return Telephony::ObservedCallResolver.new(**args) if payload['observed']

    Telephony::InboundResolver.new(**args, hint: payload['hint'].to_s)
  end
end
