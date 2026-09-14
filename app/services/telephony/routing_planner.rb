# Evalúa las reglas de enrutamiento en orden y construye el plan que ejecuta el controlador:
# pasos no terminales (agentes en paralelo, extensión, ring group) y un paso terminal (IVR, buzón, colgar).
class Telephony::RoutingPlanner
  pattr_initialize [:account!, :conversation!, :contact, :did!, :caller_e164!, :telephony_inbox]

  def plan
    steps = []
    account.telephony_routing_rules.ordered.where(enabled: true).each do |rule|
      next unless matches?(rule)

      step = build_step(rule)
      next unless step

      steps << step
      break if rule.terminal?
    end
    steps << { type: 'hangup' } unless steps.last && Telephony::RoutingRule::TERMINAL.include?(steps.last[:type])
    steps
  end

  private

  def matches?(rule)
    c = rule.conditions.to_h.stringify_keys
    tristate(c['contact_known'], contact.present?) &&
      tristate(c['open_conversation'], conversation.persisted? && conversation.status == 'open' && !new_conversation?) &&
      tristate(c['assignee_online'], assignee_online?) &&
      hours(c['business_hours']) &&
      did_matches?(c['dids']) &&
      caller_e164.start_with?(c['caller_prefix'].to_s.strip)
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
    case d['type']
    when 'assignee' then agents_step([conversation.assignee_id], rule.timeout)
    when 'agent' then agents_step([d['user_id'].to_i], rule.timeout)
    when 'team' then agents_step(account.teams.find_by(id: d['team_id'])&.members&.pluck(:id) || [], rule.timeout)
    when 'extension' then { type: 'extension', extension: d['extension'].to_s, timeout: rule.timeout }
    when 'ringgroup' then { type: 'ringgroup', number: d['number'].to_s, timeout: rule.timeout }
    when 'ivr' then { type: 'ivr', id: d['ivr_id'].to_s }
    when 'voicemail' then { type: 'voicemail', extension: d['extension'].to_s }
    when 'hangup' then { type: 'hangup' }
    end
  end

  # Solo agentes en línea con extensión; si no queda ninguno, la regla no aporta paso.
  def agents_step(user_ids, timeout)
    agents = user_ids.compact.uniq.select { |id| online?(id) && endpoints.key?(id) }
                     .map { |id| { user_id: id, extension: endpoints[id] } }
    return nil if agents.empty?

    { type: 'agents', agents: agents, timeout: timeout }
  end
end
