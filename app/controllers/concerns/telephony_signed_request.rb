# Verificación HMAC-SHA256 + timestamp de las peticiones del telephony-controller (sin sesión de usuario).
module TelephonySignedRequest
  extend ActiveSupport::Concern

  MAX_SKEW = 300

  included do
    before_action :verify_telephony_signature
  end

  private

  def verify_telephony_signature
    head :unauthorized unless telephony_signature_valid?
  end

  def telephony_signature_valid?
    secret = Telephony::Config.get('TELEPHONY_HMAC_SECRET')
    ts = request.headers['X-Telephony-Timestamp'].to_s
    sig = request.headers['X-Telephony-Signature'].to_s
    return false if secret.blank? || ts.blank? || sig.blank?
    return false if (Time.now.to_i - ts.to_i).abs > MAX_SKEW

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{request.raw_post}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, sig)
  end
end
