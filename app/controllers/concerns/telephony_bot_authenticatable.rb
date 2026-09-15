# Autenticación de la API del bot de voz: `Authorization: Bearer <token>` → cuenta dueña del token
# (Telephony::Pbx#bot_token_digest). Sin sesión de usuario ni CSRF: el bot es un servicio de la cuenta.
module TelephonyBotAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_bot!
  end

  private

  def authenticate_bot!
    @pbx = Telephony::Pbx.authenticate_bot_token(bot_token)
    return render json: { error: 'unauthorized' }, status: :unauthorized unless @pbx

    @account = @pbx.account
  end

  def bot_token
    request.authorization.to_s[/\ABearer\s+(\S+)\z/i, 1]
  end
end
