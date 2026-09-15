# Contexto de una llamada para el bot de voz (API del bot y webhook): llamada, contacto, conversación
# con sus últimos mensajes, agentes con extensión (registro SIP + presencia), equipos y ring groups.
class Telephony::BotCallContext
  LAST_MESSAGES = 5

  pattr_initialize [:projection!]

  def payload
    { call: call_payload, contact: contact_payload, conversation: conversation_payload, agents: agents_payload,
      teams: account.teams.order(:name).map { |t| { id: t.id, name: t.name } }, ringgroups: ringgroups_payload }
  end

  # Cuerpo del webhook `call.inbound`: lo justo para decidir sin leer cabeceras SIP.
  def webhook_payload
    { event: 'call.inbound', call_id: projection.external_call_id, account_id: account.id, caller_e164: projection.destination_e164,
      did: projection.did, hint: projection.hint, contact: contact_payload, conversation: conversation_payload, api: api_payload }
  end

  def api_payload
    base = "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/api/v1/telephony/bot/calls/#{projection.external_call_id}"
    { calls_url: base, route_url: "#{base}/route" }
  end

  private

  def account
    projection.account
  end

  def conversation
    projection.conversation
  end

  def contact
    conversation&.contact
  end

  def call_payload
    { id: projection.external_call_id, direction: projection.direction, state: projection.state, did: projection.did,
      caller_e164: projection.destination_e164, answered_by: projection.answered_by, routed_by: projection.routed_by }
  end

  def contact_payload
    return nil unless contact

    { id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email }
  end

  def conversation_payload
    return nil unless conversation

    assignee = conversation.assignee
    { id: conversation.id, display_id: conversation.display_id,
      url: "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/app/accounts/#{account.id}/conversations/#{conversation.display_id}",
      inbox: { id: conversation.inbox_id, name: conversation.inbox&.name },
      assignee: assignee ? { id: assignee.id, name: assignee.available_name } : nil,
      last_messages: last_messages }
  end

  def last_messages
    conversation.messages.where(message_type: %w[incoming outgoing]).reorder(created_at: :desc, id: :desc).limit(LAST_MESSAGES).reverse.map do |m|
      { sender: sender_kind(m), content: m.content, created_at: m.created_at }
    end
  end

  def sender_kind(message)
    return 'contact' if message.incoming?

    message.sender.is_a?(User) ? 'agent' : 'bot'
  end

  def agents_payload
    registration = Telephony::RegistrationStatus.new(account: account)
    availability = OnlineStatusTracker.get_available_users(account.id) || {}
    Telephony::Endpoint.where(account_id: account.id, enabled: true).includes(:user).map do |e|
      { user_id: e.user_id, name: e.user&.available_name, extension: e.endpoint, registered: registration.registered?(e.endpoint),
        online: availability[e.user_id.to_s] == 'online' }
    end
  end

  def ringgroups_payload
    Array(Telephony::ControllerClient.new.ring_groups(account_id: account.id)).map do |rg|
      { number: rg['number'].to_s, description: rg['description'].to_s }
    end
  rescue Telephony::ControllerClient::Error
    []
  end
end
