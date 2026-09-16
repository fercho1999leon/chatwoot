# Historial de llamadas SIP (Telephony::CallProjection) con los mismos filtros que la página
# "Calls": status/direction (vocabulario de la tarjeta), inbox, agente, rango de fechas y paginación.
#
# Visibilidad (M05): administradores y report_manage ven toda la cuenta. El resto ve las llamadas en las
# que PARTICIPÓ de cualquier forma (dueño actual, dueño anterior tras una transferencia, destino interno,
# invitado a una conferencia o agente al que le sonó aunque nadie contestara) y las de los inboxes de los
# que es miembro (perdidas sin dueño incluidas). Es visibilidad histórica: controlar la llamada sigue
# regido por CallProjectionPolicy.
class TelephonyCallFinder
  RESULTS_PER_PAGE = 25
  COMPLETED_REASONS = %w[completed max_duration to_ivr to_voicemail].freeze
  NO_ANSWER_REASONS = %w[no_answer agent_no_answer missed no_agents busy].freeze
  REJECTED_REASONS = %w[rejected canceled agent_hangup].freeze
  STATUS_FILTERS = {
    'in-progress' => { state: 'answered' },
    'ringing' => { state: %w[requested agent_connecting dialing ringing] },
    'completed' => { end_reason: COMPLETED_REASONS },
    'no-answer' => { end_reason: NO_ANSWER_REASONS },
    'rejected' => { end_reason: REJECTED_REASONS }
  }.freeze
  DIRECTIONS = %w[inbound outbound internal].freeze

  def initialize(current_user, current_account, params)
    @current_user = current_user
    @current_account = current_account
    @params = params
  end

  def perform
    @calls = Telephony::CallProjection.where(account_id: @current_account.id)
    filter_by_visibility
    filter_by_status
    filter_by_direction
    @calls = @calls.where(inbox_id: @params[:inbox_id]) if @params[:inbox_id].present?
    @calls = @calls.merge(involving(@params[:agent_id].to_i)) if @params[:agent_id].present?
    filter_by_date_range
    { calls: paginated, count: @calls.count }
  end

  private

  def filter_by_visibility
    return if account_wide_access?

    member_inbox_ids = @current_user.inbox_members.where(inbox: @current_account.inboxes).pluck(:inbox_id)
    @calls = @calls.merge(involving(@current_user.id).or(Telephony::CallProjection.where(inbox_id: member_inbox_ids)))
  end

  # Llamadas en las que el usuario intervino: mismas columnas que CallProjection#involved_user_ids.
  def involving(user_id)
    Telephony::CallProjection
      .where(user_id: user_id).or(Telephony::CallProjection.where(to_user_id: user_id))
      .or(Telephony::CallProjection.where(transfer_to_user_id: user_id))
      .or(Telephony::CallProjection.where(previous_user_id: user_id))
      .or(Telephony::CallProjection.where('ringing_user_ids @> ?', [user_id].to_json))
      .or(Telephony::CallProjection.where('participants @> ?', [user_id].to_json))
  end

  # custom_role es Enterprise: en CE solo cuenta el rol de administrador.
  def account_wide_access?
    account_user = Current.account_user
    return false unless account_user
    return true if account_user.administrator?

    account_user.respond_to?(:custom_role) && account_user.custom_role&.permissions&.include?('report_manage')
  end

  def filter_by_status
    status = @params[:status].to_s
    if status == 'failed'
      # Lo que display_status llama «failed»: terminadas por un motivo fuera de los tres grupos conocidos
      # (bridge_failure, controller_restart, error de la PBX…).
      @calls = @calls.where(state: 'ended').where.not(end_reason: COMPLETED_REASONS + NO_ANSWER_REASONS + REJECTED_REASONS)
      return
    end
    filter = STATUS_FILTERS[status]
    @calls = @calls.where(filter) if filter
  end

  def filter_by_direction
    @calls = @calls.where(direction: @params[:direction]) if DIRECTIONS.include?(@params[:direction].to_s)
  end

  def filter_by_date_range
    return if @params[:since].blank? || @params[:until].blank?

    @calls = @calls.where(created_at: Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i))
  end

  def paginated
    @calls.includes(:user, conversation: :contact, inbox: :channel).order(created_at: :desc).page(@params[:page] || 1).per(RESULTS_PER_PAGE)
  end
end
