# Evalúa las reglas de enrutamiento en orden y construye el plan que ejecuta el controlador:
# pasos no terminales (agentes en paralelo, extensión, ring group) y un paso terminal (IVR, buzón, colgar).
class Telephony::RoutingPlanner
  pattr_initialize [:account!, :conversation!, :contact, :did!, :caller_e164!, :telephony_inbox, :hint]
  TARGET_TYPES = %w[team agents agent ringgroup extension voicemail hangup].freeze

  def plan
    steps = []
    # find_each ignora el ORDER BY (itera por id): son pocas reglas por cuenta, se cargan en memoria.
    account.telephony_routing_rules.ordered.where(enabled: true).to_a.each do |rule|
      next unless matches?(rule)

      step = build_step(rule)
      next unless step

      steps << step
      break if rule.terminal?
    end
    steps << { type: 'hangup' } unless steps.last && Telephony::RoutingRule::TERMINAL.include?(steps.last[:type])
    steps
  end

  # Pasos para un destino elegido fuera de las reglas (API del bot). [] si ningún agente elegible;
  # la cadena del controlador sigue con su propio final (plan_hangup) si nadie contesta.
  def steps_for_target(target, timeout: 20)
    t = target.to_h.stringify_keys
    required = Telephony::RoutingRule::REQUIRED_FIELD[t['type']]
    raise CustomExceptions::Telephony::Invalid, 'invalid_target' unless TARGET_TYPES.include?(t['type'])
    raise CustomExceptions::Telephony::Invalid, 'invalid_target' if required && t[required].blank?
    raise CustomExceptions::Telephony::Invalid, 'invalid_target' if t['type'] == 'agents' && Array(t['user_ids']).empty?

    user_ids = ringing_user_ids(t)
    step = user_ids ? agents_step(user_ids, timeout.to_i.clamp(5, 120)) : pbx_step(t, timeout.to_i.clamp(5, 120))
    [step].compact
  end

  private

  def matches?(rule)
    c = rule.conditions.to_h.stringify_keys
    facts = { 'contact_known' => contact.present?, 'open_conversation' => open_conversation?, 'assignee_online' => assignee_online? }
    facts.all? { |key, fact| tristate(c[key], fact) } &&
      hours(c['business_hours']) && did_matches?(c['dids']) && caller_e164.start_with?(c['caller_prefix'].to_s.strip) &&
      hint_matches?(c['hint'])
  end

  # Pista del dialplan (CHATWOOT_HINT): texto exacto; vacío = cualquiera.
  def hint_matches?(value)
    expected = value.to_s.strip
    expected.blank? || expected == hint.to_s.strip
  end

  def open_conversation?
    conversation.status == 'open' && !new_conversation?
  end

  def tristate(value, fact)
    case value
    when 'yes' then fact
    when 'no' then !fact
    else true
    end
  end

  def hours(value)
    return true if value.blank? || value == 'any' || telephony_inbox.nil?

    value == 'out' ? telephony_inbox.out_of_office? : !telephony_inbox.out_of_office?
  end

  def did_matches?(dids)
    list = dids.to_s.split(',').map(&:strip).compact_blank
    list.empty? || list.include?(did)
  end

  # Conversación creada por esta misma llamada (sin actividad previa).
  def new_conversation?
    conversation.messages.none?
  end

  def assignee_online?
    conversation.assignee_id.present? && online?(conversation.assignee_id) && endpoints.key?(conversation.assignee_id)
  end

  def availability
    @availability ||= OnlineStatusTracker.get_available_users(account.id) || {}
  end

  def online?(user_id)
    availability[user_id.to_s] == 'online'
  end

  def endpoints
    @endpoints ||= Telephony::Endpoint.where(account_id: account.id, enabled: true).pluck(:user_id, :endpoint).to_h
  end

  def build_step(rule)
    d = rule.destination.to_h.stringify_keys
    user_ids = ringing_user_ids(d)
    return agents_step(user_ids, rule.timeout) if user_ids

    pbx_step(d, rule.timeout)
  end

  # Destinos que timbran a usuarios de Chatwoot (nil = destino de la PBX).
  def ringing_user_ids(destination)
    case destination['type']
    when 'assignee' then [conversation.assignee_id]
    when 'agent' then [destination['user_id'].to_i]
    when 'agents' then Array(destination['user_ids']).map(&:to_i)
    when 'team' then team_member_ids(destination['team_id'])
    end
  end

  def team_member_ids(team_id)
    account.teams.find_by(id: team_id)&.members&.pluck(:id) || []
  end

  def pbx_step(destination, timeout)
    case destination['type']
    when 'extension'
      step = { type: 'extension', extension: destination['extension'].to_s, timeout: timeout }
      step[:max_seconds] = destination['max_seconds'].to_i if destination['max_seconds'].present?
      step
    when 'ringgroup' then { type: 'ringgroup', number: destination['number'].to_s, timeout: timeout, expand: expand?(destination['expand']) }
    when 'ivr' then { type: 'ivr', id: destination['ivr_id'].to_s }
    when 'voicemail' then { type: 'voicemail', extension: destination['extension'].to_s }
    else { type: 'hangup' }
    end
  end

  # expand: el controlador timbra a los miembros del ring group como patas propias (por defecto);
  # false = lo timbra FreePBX (Local/<rg>@from-internal).
  def expand?(value)
    value.nil? || value == '' || ActiveModel::Type::Boolean.new.cast(value)
  end

  # Solo agentes en línea con extensión; si no queda ninguno, la regla no aporta paso.
  def agents_step(user_ids, timeout)
    agents = user_ids.compact.uniq.select { |id| online?(id) && endpoints.key?(id) }
                     .map { |id| { user_id: id, extension: endpoints[id] } }
    return nil if agents.empty?

    { type: 'agents', agents: agents, timeout: timeout }
  end
end
