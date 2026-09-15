# Historial de llamadas SIP (Telephony::CallProjection) con los mismos filtros que la página
# "Calls": status/direction (vocabulario de la tarjeta), inbox, agente, rango de fechas y paginación.
# Administradores y report_manage ven toda la cuenta; el resto, solo las suyas.
class TelephonyCallFinder
  RESULTS_PER_PAGE = 25
  STATUS_FILTERS = {
    'in-progress' => { state: 'answered' },
    'ringing' => { state: %w[requested agent_connecting dialing ringing] },
    'completed' => { end_reason: %w[completed max_duration to_ivr to_voicemail] },
    'no-answer' => { end_reason: %w[no_answer agent_no_answer missed no_agents busy] },
    'rejected' => { end_reason: %w[rejected canceled agent_hangup] }
  }.freeze

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
    @calls = @calls.where(user_id: @params[:agent_id]) if @params[:agent_id].present?
    filter_by_date_range
    { calls: paginated, count: @calls.count }
  end

  private

  def filter_by_visibility
    return if account_wide_access?

    @calls = @calls.where(user_id: @current_user.id)
  end

  # custom_role es Enterprise: en CE solo cuenta el rol de administrador.
  def account_wide_access?
    account_user = Current.account_user
    return false unless account_user
    return true if account_user.administrator?

    account_user.respond_to?(:custom_role) && account_user.custom_role&.permissions&.include?('report_manage')
  end

  def filter_by_status
    filter = STATUS_FILTERS[@params[:status].to_s]
    @calls = @calls.where(filter) if filter
  end

  def filter_by_direction
    @calls = @calls.where(direction: @params[:direction]) if %w[inbound outbound].include?(@params[:direction].to_s)
  end

  def filter_by_date_range
    return if @params[:since].blank? || @params[:until].blank?

    @calls = @calls.where(created_at: Time.zone.at(@params[:since].to_i)..Time.zone.at(@params[:until].to_i))
  end

  def paginated
    @calls.includes(:user, conversation: :contact, inbox: :channel).order(created_at: :desc).page(@params[:page] || 1).per(RESULTS_PER_PAGE)
  end
end
