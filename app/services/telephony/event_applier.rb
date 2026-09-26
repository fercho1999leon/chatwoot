# Aplica eventos/snapshots del controlador a la proyección: versiones crecientes,
# dedupe persistente por event_id y nota privada única al terminar.
class Telephony::EventApplier
  pattr_initialize [:account!]

  DuplicateEvent = Class.new(StandardError)

  # Callback firmado (controlador → Rails). Devuelve true si aplicó, false si descartó.
  # El registro del event_id y la aplicación van en UNA transacción: si aplicar falla, el id no queda
  # marcado y el reintento del controlador vuelve a aplicarlo. Los broadcasts salen tras el commit.
  def apply_event(payload)
    event_id = payload['event_id']
    return false if event_id.blank?

    applied = ActiveRecord::Base.transaction(requires_new: true) do
      register_event!(event_id)
      apply_snapshot(payload, deferred_broadcast: true)
    end
    flush_broadcasts
    applied
  rescue DuplicateEvent
    false
  end

  # Snapshot (respuesta de la API del controlador o cuerpo del callback). Con deferred_broadcast: true
  # los eventos se acumulan y los emite flush_broadcasts (después del commit de la transacción envolvente).
  def apply_snapshot(data, deferred_broadcast: false)
    data = data.to_h.stringify_keys
    projection = Telephony::CallProjection.find_by(account_id: account.id, external_call_id: data['call_id'] || data['id'])
    return false unless projection

    applied = false
    projection.with_lock do
      next unless applicable?(projection, data)

      update_projection(projection, data)
      applied = true
    end
    pending_broadcasts << projection if applied
    flush_broadcasts unless deferred_broadcast
    applied
  end

  private

  # Un event_id repetido (índice único) aborta la transacción envolvente y se descarta como duplicado.
  def register_event!(event_id)
    Telephony::ProcessedEvent.create!(event_id: event_id, created_at: Time.current)
  rescue ActiveRecord::RecordNotUnique
    raise DuplicateEvent, event_id
  end

  def pending_broadcasts
    @pending_broadcasts ||= []
  end

  def flush_broadcasts
    pending = pending_broadcasts.dup
    pending_broadcasts.clear
    pending.each { |projection| broadcast(projection) }
  end

  def applicable?(projection, data)
    return false if data['state_version'].to_i <= projection.state_version
    return false if projection.ended? && data['state'] != 'ended'

    true
  end

  COPIED_KEYS = %w[state end_reason answered_at ended_at duration_seconds transfer_to_user_id transfer_state previous_user_id
                   answered_by routed_by hint source].freeze

  def projection_attrs(data)
    attrs = data.slice(*COPIED_KEYS).symbolize_keys.merge(
      state_version: data['state_version'].to_i, last_event_id: data['event_id'], on_hold: data['on_hold'] || false,
      peer_on_hold: data['peer_on_hold'] || false, ringing_user_ids: Array(data['ringing_user_ids']), participants: Array(data['participants'])
    )
    attrs[:contact_name] = data['contact_name'] if data['contact_name'].present?
    attrs
  end

  def update_projection(projection, data)
    attrs = projection_attrs(data)
    owner_changed = owner_changed?(projection, data)
    attrs[:user_id] = data['user_id'].presence&.to_i if owner_changed
    # Los agentes que sonaban y no contestaron deben cerrar su widget: se les avisa una última vez.
    @previously_ringing = projection.ringing_user_ids + projection.participants
    became_routable = routable_now?(projection, attrs)
    projection.update!(attrs)
    hand_over_conversation(projection) if owner_changed && projection.user_id && projection.conversation
    Telephony::NoteProjector.new(projection: projection).upsert! if projection.conversation
    fetch_recording(projection, data)
    notify_bot(projection) if became_routable
  end

  # Transferencia completada o entrante contestada: la llamada cambia de dueño. También cuando queda sin dueño
  # (llamada de FreePBX transferida o devuelta a la cola): si no, el agente que la soltó seguía viéndola como suya.
  def owner_changed?(projection, data)
    data.key?('user_id') && data['user_id'].presence&.to_i != projection.user_id
  end

  # Entrante que pasa de `requested` a sonar: desde aquí POST bot/calls/:id/route ya puede aplicarse.
  # Las que enruta FreePBX (source = pbx) no admiten reroute: no se avisa al bot.
  def routable_now?(projection, attrs)
    projection.inbound? && projection.source != 'pbx' && projection.state == 'requested' && attrs[:state] == 'agent_connecting'
  end

  # Webhook opcional del bot de voz (n8n, etc.): se avisa cuando el controlador ya confirmó el plan y la llamada
  # suena (`agent_connecting`), es decir, cuando POST bot/calls/:id/route ya puede aplicarse (H13). Avisar antes,
  # al resolver la entrante, dejaba a un bot rápido con `not_reroutable`.
  def notify_bot(projection)
    return if account.telephony_pbx&.bot_webhook_url.blank?

    Telephony::BotWebhookJob.perform_later(projection.id)
  end

  # La grabación queda en la PBX al colgar: recogerla en segundo plano.
  def fetch_recording(projection, data)
    return unless projection.ended? && data['recording_name'].present? && projection.recording_state.blank?

    projection.update!(recording_name: data['recording_name'], recording_state: 'stored')
    # Asterisk cierra el archivo justo después de colgar: sin la espera el primer intento suele fallar.
    Telephony::RecordingFetchJob.set(wait: 5.seconds).perform_later(projection.id)
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
