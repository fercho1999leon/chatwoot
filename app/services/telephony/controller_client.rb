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
    GlobalConfigService.load('TELEPHONY_CONTROLLER_URL', '')
  end

  def self.token
    GlobalConfigService.load('TELEPHONY_SERVICE_TOKEN', '')
  end

  def create_call(payload)
    post('/internal/calls', payload)
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

  def dtmf(id, digits)
    post("/internal/calls/#{id}/dtmf", { digits: digits })
  end

  def browser_session(account_id:, user_id:)
    post('/internal/browser_session', { account_id: account_id, user_id: user_id })
  end

  def upsert_endpoint(payload)
    request(:put, '/internal/endpoints', body: payload)
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
      headers: { 'Authorization' => "Bearer #{self.class.token}", 'Content-Type' => 'application/json' },
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
end
