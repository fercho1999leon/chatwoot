# Extensiones con contacto SIP vivo en la PBX según el controlador ('Avail'), cacheado 10 s: lo consultan
# el selector de agentes del widget y la API del bot en cada llamada, y el estado no cambia más rápido.
class Telephony::RegistrationStatus
  TTL = 10.seconds

  pattr_initialize [:account!]

  def registered?(extension)
    agents[extension.to_s].to_s == 'Avail'
  end

  private

  def agents
    @agents ||= Rails.cache.fetch("telephony:registration:#{account.id}", expires_in: TTL) { fetch }
  end

  def fetch
    Telephony::ControllerClient.new.status(account_id: account.id).to_h['agents'].to_h
  rescue Telephony::ControllerClient::Error => e
    Rails.logger.warn("telephony: sin estado de registro para la cuenta #{account.id}: #{e.message}")
    {}
  end
end
