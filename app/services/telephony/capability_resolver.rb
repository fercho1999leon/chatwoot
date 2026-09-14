# Decide si un usuario puede llamar desde una conversación y por qué no.
class Telephony::CapabilityResolver
  pattr_initialize [:account!, :user!, :conversation!]

  def resolve
    reason = first_blocker
    active = reason.nil? ? active_call : nil
    {
      enabled: feature_enabled? && inbox_enabled?,
      can_call: reason.nil? && active.nil?,
      reason: reason || (active ? 'agent_busy' : nil),
      destination_masked: destination_masked,
      sip_ws_url: GlobalConfigService.load('TELEPHONY_SIP_WS_URL', ''),
      max_call_seconds: GlobalConfigService.load('TELEPHONY_MAX_CALL_SECONDS', '3600').to_i,
      active_call: active&.push_event_data
    }
  end

  def feature_enabled?
    account.feature_enabled?('telephony_calls') && Telephony::ControllerClient.configured?
  end

  def inbox_enabled?
    Telephony::InboxSetting.exists?(account_id: account.id, inbox_id: conversation.inbox_id, enabled: true)
  end

  def endpoint
    @endpoint ||= Telephony::Endpoint.find_by(account_id: account.id, user_id: user.id, enabled: true)
  end

  def destination
    conversation.contact&.phone_number.presence
  end

  private

  def first_blocker
    return 'feature_disabled' unless feature_enabled?
    return 'inbox_not_enabled' unless inbox_enabled?
    return 'no_endpoint' unless endpoint
    return 'no_phone' unless destination

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
