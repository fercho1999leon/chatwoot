# Llamada interna agente → agente (sin conversación): ambos deben tener extensión vinculada.
class Telephony::InternalCallCreator
  pattr_initialize [:account!, :user!, :to_user!]

  def perform
    ensure_allowed!
    projection = Telephony::CallProjection.create!(
      account: account, user: user, to_user: to_user, external_call_id: SecureRandom.uuid, state: 'requested', state_version: 0,
      destination_e164: to_endpoint.endpoint, direction: 'internal', contact_name: user.available_name,
      ringing_user_ids: [to_user.id], requested_at: Time.current
    )
    remote = Telephony::ControllerClient.new.create_call(
      call_id: projection.external_call_id, account_id: account.id, user_id: user.id, conversation_id: 0, conversation_display_id: 0,
      destination_e164: to_endpoint.endpoint, direction: 'internal', to_user_id: to_user.id, contact_name: user.available_name
    )
    Telephony::EventApplier.new(account: account).apply_snapshot(remote)
    projection.reload
  rescue Telephony::ControllerClient::Error => e
    projection&.update!(state: 'ended', end_reason: 'policy_denied', ended_at: Time.current)
    raise CustomExceptions::Telephony::Conflict, e.code if e.status == 409
    raise CustomExceptions::Telephony::Unavailable, e.code if e.status == 503

    raise CustomExceptions::Telephony::Invalid, e.code
  end

  private

  def to_endpoint
    @to_endpoint ||= Telephony::Endpoint.find_by(account_id: account.id, user_id: to_user.id, enabled: true)
  end

  def ensure_allowed!
    raise CustomExceptions::Telephony::Invalid, 'same_user' if to_user.id == user.id
    raise CustomExceptions::Telephony::Invalid, 'no_endpoint' unless Telephony::Endpoint.exists?(account_id: account.id, user_id: user.id, enabled: true)
    raise CustomExceptions::Telephony::Invalid, 'target_no_endpoint' unless to_endpoint
    raise CustomExceptions::Telephony::Conflict, 'agent_busy' if Telephony::CallProjection.active.exists?(account_id: account.id, user_id: user.id)
  end
end
