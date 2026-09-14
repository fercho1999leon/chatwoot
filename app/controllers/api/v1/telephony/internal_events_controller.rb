# Callback del telephony-controller (HMAC-SHA256 + timestamp). Sin sesión de usuario.
class Api::V1::Telephony::InternalEventsController < ActionController::API
  MAX_SKEW = 300

  before_action :verify_signature

  def create
    payload = JSON.parse(request.raw_post)
    account = Account.find_by(id: payload['account_id'])
    return render json: { applied: false }, status: :ok unless account

    applied = Telephony::EventApplier.new(account: account).apply_event(payload)
    render json: { applied: applied }
  rescue JSON::ParserError
    head :unprocessable_entity
  end

  private

  def verify_signature
    head :unauthorized unless signature_valid?
  end

  def signature_valid?
    secret = GlobalConfigService.load('TELEPHONY_HMAC_SECRET', '')
    ts = request.headers['X-Telephony-Timestamp'].to_s
    sig = request.headers['X-Telephony-Signature'].to_s
    return false if secret.blank? || ts.blank? || sig.blank?
    return false if (Time.now.to_i - ts.to_i).abs > MAX_SKEW

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{ts}.#{request.raw_post}")}"
    ActiveSupport::SecurityUtils.secure_compare(expected, sig)
  end
end
