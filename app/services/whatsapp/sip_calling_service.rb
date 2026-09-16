# WhatsApp Business Calling por SIP (CE): Meta cursa las llamadas de WhatsApp contra la PBX
# (Asterisk/FreePBX) por SIP/TLS en vez de por webhooks + WebRTC. Este servicio:
#   enable!  → activa calling + SIP en el número (Call Settings API) apuntando a la PBX,
#              lee la contraseña SIP generada por Meta y provisiona la troncal wa-<phone_number_id>.
#   disable! → desactiva SIP en Meta y retira la troncal.
# La contraseña nunca se guarda en Chatwoot: viaja al telephony-controller (PBX por cuenta).
class Whatsapp::SipCallingService
  SIP_PORT = 5061
  CONFIG_KEY = 'sip_calling'.freeze

  class Error < StandardError; end

  pattr_initialize [:channel!]

  def enable!(hostname:)
    raise Error, 'not_whatsapp_cloud' unless channel.voice_calling_supported?
    raise Error, 'no_pbx' unless pbx&.configured?

    update_settings(calling: { status: 'ENABLED', call_icon_visibility: 'DEFAULT', callback_permission_status: 'ENABLED',
                               sip: { status: 'ENABLED', servers: [{ hostname: hostname, port: SIP_PORT }] } })
    password = fetch_sip_password
    result = Telephony::ControllerClient.new.upsert_whatsapp_trunk(
      account_id: channel.account_id, phone_number_id: phone_number_id, number: business_number, password: password
    )
    save_config('enabled' => true, 'hostname' => hostname, 'synced_at' => Time.current.iso8601,
                'provision_error' => result.dig('provision', 'error'))
  end

  # Meta rota la contraseña solo si se vuelve a activar SIP; este método la relee y la reenvía a la PBX.
  def resync!
    config = current_config
    raise Error, 'not_enabled' unless config['enabled']

    enable!(hostname: config['hostname'])
  end

  def disable!
    update_settings(calling: { sip: { status: 'DISABLED' } })
    Telephony::ControllerClient.new.delete_whatsapp_trunk(account_id: channel.account_id, phone_number_id: phone_number_id)
    save_config('enabled' => false, 'synced_at' => Time.current.iso8601, 'provision_error' => nil)
  end

  # Estado en Meta (sin credenciales) para mostrarlo en la UI.
  def remote_status
    response = HTTParty.get("#{settings_path}?fields=calling", headers: api_headers)
    raise Error, meta_error(response, 'settings_unavailable') unless response.success?

    response.parsed_response['calling'] || {}
  end

  def current_config
    channel.provider_config[CONFIG_KEY] || {}
  end

  def phone_number_id
    channel.provider_config['phone_number_id'].to_s
  end

  private

  def pbx
    Telephony::Pbx.find_by(account_id: channel.account_id)
  end

  def business_number
    channel.phone_number.to_s.delete(' ')
  end

  def update_settings(body)
    response = HTTParty.post(settings_path, headers: api_headers, body: body.to_json)
    raise Error, meta_error(response, 'settings_update_failed') unless response.success?

    response.parsed_response
  end

  def fetch_sip_password
    response = HTTParty.get("#{settings_path}?include_sip_credentials=true", headers: api_headers)
    raise Error, meta_error(response, 'sip_credentials_unavailable') unless response.success?

    servers = response.parsed_response.dig('calling', 'sip', 'servers') || []
    password = servers.filter_map { |srv| srv['sip_user_password'] }.first
    raise Error, 'sip_password_missing' if password.blank?

    password
  end

  def save_config(attrs)
    channel.update!(provider_config: channel.provider_config.merge(CONFIG_KEY => current_config.merge(attrs)))
    channel.provider_config[CONFIG_KEY]
  end

  def settings_path
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{version}/#{phone_number_id}/settings"
  end

  def api_headers
    { 'Authorization' => "Bearer #{channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def meta_error(response, default)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] : nil
    Rails.logger.error("[WHATSAPP SIP] #{default}: status=#{response.code} body=#{response.body.to_s[0, 300]}")
    error.is_a?(Hash) && error['message'].present? ? error['message'] : default
  end
end
