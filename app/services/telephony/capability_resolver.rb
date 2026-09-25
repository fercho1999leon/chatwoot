# Decide si un usuario puede llamar desde una conversación y por qué no.
class Telephony::CapabilityResolver
  pattr_initialize [:account!, :user!, :conversation!]

  def resolve
    reason = first_blocker
    active = reason.nil? ? active_call : nil
    base_capabilities.merge(
      enabled: feature_enabled? && inbox_enabled?,
      can_call: reason.nil? && active.nil?,
      reason: reason || (active ? 'agent_busy' : nil),
      active_call: active&.push_event_data
    )
  end

  def feature_enabled?
    account.feature_enabled?('telephony_calls') && Telephony::ControllerClient.configured? && pbx_configured? &&
      (whatsapp_sip? || telephony_channel&.configured?)
  end

  # Conversación de un inbox WhatsApp Cloud con Business Calling por SIP: la llamada va por la
  # troncal wa-<phone_number_id> de la PBX, no por el carrier ni por la lista de inboxes permitidos.
  def whatsapp_sip?
    return @whatsapp_sip if defined?(@whatsapp_sip)

    channel = conversation.inbox&.channel
    @whatsapp_sip = channel.is_a?(Channel::Whatsapp) && channel.provider_config.dig('sip_calling', 'enabled') == true
  end

  def whatsapp_phone_number_id
    whatsapp_sip? ? conversation.inbox.channel.provider_config['phone_number_id'].to_s : nil
  end

  def pbx_configured?
    account.telephony_pbx&.configured? || false
  end

  # Inbox de tipo Telephony de la cuenta (la troncal). Uno por cuenta en el MVP.
  def telephony_channel
    @telephony_channel ||= Channel::Telephony.where(account_id: account.id).order(:id).first
  end

  def inbox_enabled?
    whatsapp_sip? || telephony_channel&.allows_inbox?(conversation.inbox_id) || false
  end

  # El agente debe ser colaborador del inbox Telephony y tener extensión provisionada.
  def endpoint
    @endpoint ||= Telephony::Endpoint.find_by(account_id: account.id, user_id: user.id, enabled: true)
  end

  def destination
    conversation.contact&.phone_number.presence
  end

  private

  def base_capabilities
    {
      destination_masked: destination_masked,
      max_call_seconds: account.telephony_pbx&.max_call_seconds || 3600
    }
  end

  # pattr_initialize deja los readers privados: evaluar aquí, no en lambdas externas.
  def blockers
    {
      'feature_disabled' => account.feature_enabled?('telephony_calls') && Telephony::ControllerClient.configured?,
      'no_pbx' => pbx_configured?,
      'no_trunk' => whatsapp_sip? || telephony_channel&.configured?,
      'inbox_not_enabled' => inbox_enabled?,
      'no_endpoint' => endpoint.present?,
      'no_phone' => destination.present?
    }
  end

  def first_blocker
    blockers.each { |reason, ok| return reason unless ok }
    nil
  end

  # Si la proyección dice "activa", se confirma con el controlador (fuente de verdad):
  # un callback perdido o tardío no debe bloquear al agente para siempre.
  def active_call
    projection = Telephony::CallProjection.active.find_by(account_id: account.id, user_id: user.id)
    return nil unless projection

    begin
      snapshot = Telephony::ControllerClient.new.call(projection.external_call_id)
      Telephony::EventApplier.new(account: account).apply_snapshot(snapshot)
      projection.reload
    rescue Telephony::ControllerClient::Error => e
      if e.status == 404
        projection.update!(state: 'ended', end_reason: 'controller_restart', ended_at: Time.current)
      else
        Rails.logger.warn("telephony: no se pudo confirmar la llamada activa #{projection.external_call_id}: #{e.message}")
      end
    end
    projection.ended? ? nil : projection
  end

  def destination_masked
    d = destination
    return nil if d.blank?
    return '***' if d.length <= 7

    "#{d[0, 5]}****#{d[-3..]}"
  end
end
