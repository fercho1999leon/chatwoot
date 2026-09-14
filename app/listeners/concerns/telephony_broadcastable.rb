# Eventos de telefonía (SIP/WebRTC) para ActionCableListener: solo al agente dueño
# de la llamada, nunca a toda la cuenta ni a los administradores.
module TelephonyBroadcastable
  def telephony_call_created(event)
    broadcast_telephony_call(event)
  end

  def telephony_call_updated(event)
    broadcast_telephony_call(event)
  end

  def telephony_call_ended(event)
    broadcast_telephony_call(event)
  end

  private

  # Dueño actual + agente destino de una transferencia en curso + dueño anterior (para que
  # su widget se cierre al completarse) + agentes a los que suena una entrante (y los que
  # dejaron de sonar). Nunca a toda la cuenta.
  def broadcast_telephony_call(event)
    call = event.data[:telephony_call]
    user_ids = [call.user_id, call.transfer_to_user_id, call.previous_user_id, *call.ringing_user_ids,
                *Array(event.data[:previously_ringing])].compact.uniq
    tokens = User.where(id: user_ids).pluck(:pubsub_token)
    broadcast(call.account, tokens, event.name, call.push_event_data)
  end
end
