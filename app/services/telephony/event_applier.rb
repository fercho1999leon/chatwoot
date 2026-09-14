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
    call_id = data['call_id'] || data['id']
    projection = Telephony::CallProjection.find_by(account_id: account.id, external_call_id: call_id)
    return false unless projection

    version = data['state_version'].to_i
    applied = false
    projection.with_lock do
      next if version <= projection.state_version
      next if projection.ended? && data['state'] != 'ended'

      projection.assign_attributes(
        state: data['state'], state_version: version, end_reason: data['end_reason'],
        answered_at: data['answered_at'], ended_at: data['ended_at'], duration_seconds: data['duration_seconds'],
        last_event_id: data['event_id']
      )
      projection.save!
      Telephony::NoteProjector.new(projection: projection).upsert! if projection.ended?
      applied = true
    end
    broadcast(projection, data['state']) if applied
    applied
  end

  private

  def broadcast(projection, state)
    event = case state
            when 'ended' then Events::Types::TELEPHONY_CALL_ENDED
            when 'requested', 'agent_connecting' then Events::Types::TELEPHONY_CALL_CREATED
            else Events::Types::TELEPHONY_CALL_UPDATED
            end
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, telephony_call: projection)
  end
end
