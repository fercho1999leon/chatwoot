# Crea la intención de llamada: idempotencia por (cuenta, usuario, clave, hash del payload),
# resuelve destino/permisos en el servidor y delega la originación al controlador.
class Telephony::CallCreator
  IDEMPOTENCY_TTL = 24.hours

  pattr_initialize [:account!, :user!, :conversation!, :idempotency_key!]

  def perform
    raise CustomExceptions::Telephony::Invalid, 'missing_idempotency_key' if idempotency_key.blank?

    resolver = Telephony::CapabilityResolver.new(account: account, user: user, conversation: conversation)
    destination = resolver.destination
    hash = Digest::SHA256.hexdigest([account.id, user.id, conversation.id, destination].join('|'))

    # Idempotencia ANTES de capacidades: un reintento con la misma clave debe devolver la
    # misma llamada aunque ahora el agente figure ocupado (por esa misma llamada).
    existing = Telephony::IdempotencyKey.find_by(account_id: account.id, user_id: user.id, key: idempotency_key)
    if existing
      raise CustomExceptions::Telephony::Conflict, 'idempotency_mismatch' if existing.payload_hash != hash

      return [Telephony::CallProjection.find_by!(account_id: account.id, external_call_id: existing.call_id), false]
    end

    caps = resolver.resolve
    raise CustomExceptions::Telephony::Conflict, 'agent_busy' if caps[:reason] == 'agent_busy'
    raise CustomExceptions::Telephony::Invalid, caps[:reason] unless caps[:enabled] && caps[:reason].nil?

    call_id = SecureRandom.uuid
    projection = ActiveRecord::Base.transaction do
      Telephony::IdempotencyKey.create!(account: account, user: user, key: idempotency_key, payload_hash: hash,
                                        call_id: call_id, expires_at: IDEMPOTENCY_TTL.from_now)
      Telephony::CallProjection.create!(
        account: account, user: user, conversation: conversation, inbox_id: conversation.inbox_id,
        external_call_id: call_id, state: 'requested', state_version: 0, destination_e164: destination, requested_at: Time.current
      )
    end

    begin
      remote = Telephony::ControllerClient.new.create_call(
        call_id: call_id, account_id: account.id, user_id: user.id,
        conversation_id: conversation.id, conversation_display_id: conversation.display_id,
        inbox_id: conversation.inbox_id, contact_id: conversation.contact_id, destination_e164: destination
      )
    rescue Telephony::ControllerClient::Error => e
      projection.update!(state: 'ended', end_reason: e.code == 'pbx_unreachable' ? 'pbx_unreachable' : 'policy_denied', ended_at: Time.current)
      raise CustomExceptions::Telephony::Conflict, e.code if e.status == 409
      raise CustomExceptions::Telephony::Unavailable, e.code if e.status == 503

      raise CustomExceptions::Telephony::Invalid, e.code
    end

    Telephony::EventApplier.new(account: account).apply_snapshot(remote)
    [projection.reload, true]
  end
end
