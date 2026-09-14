# Aplica eventos/snapshots del controlador a la proyección: versiones crecientes,
# dedupe persistente por event_id y nota privada única al terminar.
class Telephony::EventApplier
  pattr_initialize [:account!]

  # Callback firmado (controlador → Rails). Devuelve true si aplicó, false si descartó.
  def apply_event(payload)
    event_id = payload['event_id']
    return false if event_id.blank?

    begin
      Telephony::ProcessedEvent.create!(event_id: event_id, created_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      return false
    end
    apply_snapshot(payload)
  end

  # Snapshot (respuesta de la API del controlador o cuerpo del callback).
  def apply_snapshot(data)
    data = data.to_h.stringify_keys
    projection = Telephony::CallProjection.find_by(account_id: account.id, external_call_id: data['call_id'] || data['id'])
    return false unless projection

    applied = false
    projection.with_lock do
      next unless applicable?(projection, data)

      update_projection(projection, data)
      applied = true
    end
    broadcast(projection) if applied
    applied
  end

  private

  def applicable?(projection, data)
    return false if data['state_version'].to_i <= projection.state_version
    return false if projection.ended? && data['state'] != 'ended'

    true
  end

  COPIED_KEYS = %w[state end_reason answered_at ended_at duration_seconds transfer_to_user_id transfer_state previous_user_id
                   answered_by].freeze

  def projection_attrs(data)
    attrs = data.slice(*COPIED_KEYS).symbolize_keys.merge(
      state_version: data['state_version'].to_i, last_event_id: data['event_id'], on_hold: data['on_hold'] || false,
      ringing_user_ids: Array(data['ringing_user_ids'])
    )
    attrs[:contact_name] = data['contact_name'] if data['contact_name'].present?
    attrs
  end

  def update_projection(projection, data)
    attrs = projection_attrs(data)
    # Transferencia completada o entrante contestada: la llamada cambia de dueño.
    owner_changed = data['user_id'].present? && data['user_id'].to_i != projection.user_id
    attrs[:user_id] = data['user_id'].to_i if owner_changed
    # Los agentes que sonaban y no contestaron deben cerrar su widget: se les avisa una última vez.
    @previously_ringing = projection.ringing_user_ids
    projection.update!(attrs)
    hand_over_conversation(projection) if owner_changed
    Telephony::NoteProjector.new(projection: projection).upsert!
  end

  # El agente que recibe la llamada pasa a llevar la conversación: asignado y participante.
  def hand_over_conversation(projection)
    conversation = projection.conversation
    user = projection.user
    return unless conversation && user

    return if conversation.inbox.assignable_agents.exclude?(user)

    conversation.update!(assignee: user) if conversation.assignee_id != user.id
    ConversationParticipant.find_or_create_by!(conversation: conversation, user: user)
  end

  def broadcast(projection)
    event = case projection.state
            when 'ended' then Events::Types::TELEPHONY_CALL_ENDED
            when 'requested', 'agent_connecting' then Events::Types::TELEPHONY_CALL_CREATED
            else Events::Types::TELEPHONY_CALL_UPDATED
            end
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, telephony_call: projection, previously_ringing: @previously_ringing || [])
  end
end
