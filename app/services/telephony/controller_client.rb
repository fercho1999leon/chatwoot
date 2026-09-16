# Cliente HTTP hacia el telephony-controller (API interna, Bearer de servicio).
# Config: TELEPHONY_CONTROLLER_URL, TELEPHONY_SERVICE_TOKEN (ENV o InstallationConfig).
class Telephony::ControllerClient
  class Error < StandardError
    attr_reader :status, :code

    def initialize(status, code)
      @status = status
      @code = code
      super("telephony-controller #{status}: #{code}")
    end
  end

  NETWORK_ERRORS = [Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, SocketError].freeze

  def self.configured?
    base_url.present? && token.present?
  end

  def self.base_url
    Telephony::Config.get('TELEPHONY_CONTROLLER_URL')
  end

  def self.token
    Telephony::Config.get('TELEPHONY_SERVICE_TOKEN')
  end

  def create_call(payload)
    post('/internal/calls', payload.compact) # los opcionales ausentes no viajan como null
  end

  def call(id)
    get("/internal/calls/#{id}")
  end

  def active_call(account_id:, user_id:)
    get('/internal/calls/active', account_id: account_id, user_id: user_id)
  end

  def hangup(id, requested_by_user_id:)
    post("/internal/calls/#{id}/hangup", { requested_by_user_id: requested_by_user_id })
  end

  def join(id, user_id:)
    post("/internal/calls/#{id}/join", { user_id: user_id })
  end

  def leave(id, user_id:)
    post("/internal/calls/#{id}/leave", { user_id: user_id })
  end

  def ring_me(id, user_id:)
    post("/internal/calls/#{id}/ring_me", { user_id: user_id })
  end

  def dtmf(id, digits)
    post("/internal/calls/#{id}/dtmf", { digits: digits })
  end

  def browser_session(account_id:, user_id:)
    post('/internal/browser_session', { account_id: account_id, user_id: user_id })
  end

  def upsert_endpoint(payload)
    request(:put, '/internal/endpoints', body: payload)
  end

  def delete_endpoint(account_id:, user_id:)
    request(:delete, '/internal/endpoints', body: { account_id: account_id, user_id: user_id })
  end

  def extensions(account_id:)
    get('/internal/extensions', account_id: account_id)
  end

  def ring_groups(account_id:)
    get('/internal/ringgroups', account_id: account_id)
  end

  def ivrs(account_id:)
    get('/internal/ivrs', account_id: account_id)
  end

  # Descarga (streaming a un archivo temporal) la grabación almacenada en la PBX.
  def download_recording(id, to:)
    raise Error.new(503, 'not_configured') unless self.class.configured?

    response = File.open(to, 'wb') do |file|
      HTTParty.get("#{self.class.base_url.chomp('/')}/internal/calls/#{id}/recording",
                   headers: { 'Authorization' => "Bearer #{self.class.token}" }, timeout: 120, stream_body: true) do |chunk|
        file.write(chunk)
      end
    end
    # El cuerpo de un error también se escribió al archivo: de ahí sale el código (no_recording, pbx_recording_404…).
    raise Error.new(response.code, error_code(safe_json(File.read(to))) || 'recording_unavailable') unless response.success?

    response.headers['content-type']
  rescue *NETWORK_ERRORS
    raise Error.new(503, 'pbx_unreachable')
  end

  def delete_recording(id)
    request(:delete, "/internal/calls/#{id}/recording")
  end

  def pbx(account_id:)
    get('/internal/pbx', account_id: account_id)
  end

  def upsert_pbx(payload)
    request(:put, '/internal/pbx', body: payload)
  end

  def test_pbx(payload)
    post('/internal/pbx/test', payload)
  end

  def delete_pbx(account_id:)
    request(:delete, '/internal/pbx', query: { account_id: account_id })
  end

  def upsert_trunk(payload)
    request(:put, '/internal/trunk', body: payload)
  end

  # WhatsApp Business Calling por SIP: troncal wa-<phone_number_id> en la PBX.
  def whatsapp_trunks(account_id:)
    get('/internal/whatsapp_trunks', account_id: account_id)
  end

  def upsert_whatsapp_trunk(payload)
    request(:put, '/internal/whatsapp_trunks', body: payload)
  end

  def delete_whatsapp_trunk(account_id:, phone_number_id:)
    request(:delete, '/internal/whatsapp_trunks', query: { account_id: account_id, phone_number_id: phone_number_id })
  end

  def status(account_id:)
    get('/internal/status', account_id: account_id)
  end

  def hold(id, hold:)
    post("/internal/calls/#{id}/hold", { hold: hold })
  end

  def transfer(id, to_user_id:)
    post("/internal/calls/#{id}/transfer", { to_user_id: to_user_id })
  end

  def cancel_transfer(id)
    post("/internal/calls/#{id}/transfer/cancel", {})
  end

  # Reenruta una entrante atendida por una pata sin usuario (IA/extensión): cliente a espera y nuevo plan.
  def reroute(id, steps:, by:, note: nil)
    post("/internal/calls/#{id}/reroute", { steps: steps, by: by, note: note }.compact)
  end

  private

  def get(path, query = {})
    request(:get, path, query: query)
  end

  def post(path, body)
    request(:post, path, body: body)
  end

  def request(method, path, query: {}, body: nil)
    raise Error.new(503, 'not_configured') unless self.class.configured?

    response = perform_request(method, path, query, body)
    parsed = parse(response)
    return parsed if response.success?

    raise Error.new(response.code, error_code(parsed))
  rescue *NETWORK_ERRORS => e
    Rails.logger.error("telephony-controller inalcanzable: #{e.class}")
    raise Error.new(503, 'pbx_unreachable')
  end

  def perform_request(method, path, query, body)
    HTTParty.public_send(
      method,
      "#{self.class.base_url.chomp('/')}#{path}",
      headers: { 'Authorization' => "Bearer #{self.class.token}" }.merge(body ? { 'Content-Type' => 'application/json' } : {}),
      query: query.presence,
      body: body&.to_json,
      timeout: 8
    )
  end

  def parse(response)
    parsed = response.parsed_response
    parsed.is_a?(String) && parsed.present? ? JSON.parse(parsed) : parsed
  rescue JSON::ParserError
    nil
  end

  def error_code(parsed)
    parsed.is_a?(Hash) ? (parsed['error'] || 'error') : 'error'
  end

  def safe_json(text)
    JSON.parse(text)
  rescue JSON::ParserError
    nil
  end
end
