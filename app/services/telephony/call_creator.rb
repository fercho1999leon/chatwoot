# Crea la intención de llamada: idempotencia por (cuenta, usuario, clave, hash del payload),
# resuelve destino/permisos en el servidor y delega la originación al controlador.
class Telephony::CallCreator
  IDEMPOTENCY_TTL = 24.hours

  pattr_initialize [:account!, :user!, :conversation!, :idempotency_key!]

  # => [projection, created?]
  def perform
    raise CustomExceptions::Telephony::Invalid, 'missing_idempotency_key' if idempotency_key.blank?

    existing = find_existing
    return [existing, false] if existing

    ensure_allowed!
    projection = persist_intent
    originate(projection)
    [projection.reload, true]
  end

  private

  def resolver
    @resolver ||= Telephony::CapabilityResolver.new(account: account, user: user, conversation: conversation)
  end

  def destination
    resolver.destination
  end

  def payload_hash
    @payload_hash ||= Digest::SHA256.hexdigest([account.id, user.id, conversation.id, destination].join('|'))
  end

  # Idempotencia ANTES de capacidades: un reintento con la misma clave debe devolver la
  # misma llamada aunque ahora el agente figure ocupado (por esa misma llamada).
  def find_existing
    key = Telephony::IdempotencyKey.find_by(account_id: account.id, user_id: user.id, key: idempotency_key)
    return nil unless key
    raise CustomExceptions::Telephony::Conflict, 'idempotency_mismatch' if key.payload_hash != payload_hash

    Telephony::CallProjection.find_by!(account_id: account.id, external_call_id: key.call_id)
  end

  def ensure_allowed!
    caps = resolver.resolve
    raise CustomExceptions::Telephony::Conflict, 'agent_busy' if caps[:reason] == 'agent_busy'
    raise CustomExceptions::Telephony::Invalid, caps[:reason] unless caps[:enabled] && caps[:reason].nil?
  end

  def persist_intent
    ActiveRecord::Base.transaction do
      call_id = SecureRandom.uuid
      Telephony::IdempotencyKey.create!(account: account, user: user, key: idempotency_key, payload_hash: payload_hash,
                                        call_id: call_id, expires_at: IDEMPOTENCY_TTL.from_now)
      Telephony::CallProjection.create!(
        account: account, user: user, conversation: conversation, inbox_id: conversation.inbox_id,
        external_call_id: call_id, state: 'requested', state_version: 0, destination_e164: destination, requested_at: Time.current
      )
    end
  end

  def originate(projection)
    remote = Telephony::ControllerClient.new.create_call(
      call_id: projection.external_call_id, account_id: account.id, user_id: user.id,
      conversation_id: conversation.id, conversation_display_id: conversation.display_id,
      inbox_id: conversation.inbox_id, contact_id: conversation.contact_id, destination_e164: destination,
      whatsapp_phone_number_id: resolver.whatsapp_phone_number_id
    )
    Telephony::EventApplier.new(account: account).apply_snapshot(remote)
  rescue Telephony::ControllerClient::Error => e
    fail_intent(projection, e)
  end

  def fail_intent(projection, error)
    reason = error.code == 'pbx_unreachable' ? 'pbx_unreachable' : 'policy_denied'
    projection.update!(state: 'ended', end_reason: reason, ended_at: Time.current)
    raise CustomExceptions::Telephony::Conflict, error.code if error.status == 409
    raise CustomExceptions::Telephony::Unavailable, error.code if error.status == 503

    raise CustomExceptions::Telephony::Invalid, error.code
  end
end
