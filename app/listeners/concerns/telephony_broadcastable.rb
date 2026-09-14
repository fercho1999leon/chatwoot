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

  def broadcast_telephony_call(event)
    call = event.data[:telephony_call]
    broadcast(call.account, [call.user.pubsub_token], event.name, call.push_event_data)
  end
end
