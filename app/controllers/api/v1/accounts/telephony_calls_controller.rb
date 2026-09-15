class Api::V1::Accounts::TelephonyCallsController < Api::V1::Accounts::Telephony::BaseController
  before_action :fetch_call, only: [:show, :hangup, :dtmf, :hold, :unhold, :transfer, :cancel_transfer, :recording, :answer, :join, :leave]

  # Llamada viva del usuario: la suya o una entrante que le está sonando (ringing_user_ids).
  def active
    scope = Telephony::CallProjection.active.where(account_id: Current.account.id)
    @telephony_call = scope.find_by(user_id: Current.user.id) ||
                      scope.where('ringing_user_ids @> ?', [Current.user.id].to_json).order(:id).last
    return render json: nil unless @telephony_call

    refresh_from_controller
    render :show
  end

  def show
    refresh_from_controller unless @telephony_call.ended?
    render :show
  end

  # POST telephony_calls { to_user_id } — llamada interna a otro agente.
  def create
    to_user = Current.account.users.find(params.require(:to_user_id))
    @telephony_call = Telephony::InternalCallCreator.new(account: Current.account, user: Current.user, to_user: to_user).perform
    render :show, status: :created
  end

  # Unirse (yo) o invitar (a otro) a una llamada en curso: conferencia.
  def join
    target = params[:user_id].present? ? Current.account.users.find(params[:user_id]) : Current.user
    unless target == Current.user || @telephony_call.user_id == Current.user.id || Current.account_user.administrator?
      raise Pundit::NotAuthorizedError
    end

    apply_remote { telephony_client.join(@telephony_call.external_call_id, user_id: target.id) }
  end

  def leave
    apply_remote { telephony_client.leave(@telephony_call.external_call_id, user_id: Current.user.id) }
  end

  def hangup
    unless @telephony_call.ended?
      remote = telephony_client.hangup(@telephony_call.external_call_id, requested_by_user_id: Current.user.id)
      Telephony::EventApplier.new(account: Current.account).apply_snapshot(remote)
      @telephony_call.reload
    end
    render :show
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def dtmf
    digits = params.require(:digits).to_s
    raise CustomExceptions::Telephony::Invalid, 'invalid_digits' unless digits.match?(/\A[0-9A-D*#]{1,32}\z/)
    raise CustomExceptions::Telephony::Conflict, 'not_answered' unless @telephony_call.state == 'answered'

    telephony_client.dtmf(@telephony_call.external_call_id, digits)
    head :accepted
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Conflict, e.code if e.status == 409

    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def hold
    apply_remote { telephony_client.hold(@telephony_call.external_call_id, hold: true) }
  end

  def unhold
    apply_remote { telephony_client.hold(@telephony_call.external_call_id, hold: false) }
  end

  def transfer
    to_user = Current.account.users.find(params.require(:to_user_id))
    unless Telephony::Endpoint.exists?(account_id: Current.account.id, user_id: to_user.id, enabled: true)
      raise CustomExceptions::Telephony::Invalid, 'no_endpoint'
    end
    # Sin acceso al inbox no vería la conversación (ConversationParticipant lo exige).
    raise CustomExceptions::Telephony::Invalid, 'not_inbox_member' if @telephony_call.conversation.inbox.assignable_agents.exclude?(to_user)

    apply_remote { telephony_client.transfer(@telephony_call.external_call_id, to_user_id: to_user.id) }
  end

  # La invitación SIP se perdió (recarga/red): volver a invitar. Entrante que me suena o mi propia llamada.
  def answer
    mine = @telephony_call.user_id == Current.user.id || @telephony_call.ringing_user_ids.include?(Current.user.id)
    raise CustomExceptions::Telephony::Invalid, 'not_ringing_you' unless mine

    apply_remote { telephony_client.ring_me(@telephony_call.external_call_id, user_id: Current.user.id) }
  end

  # Borra la grabación de una llamada (administradores).
  def recording
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?

    @telephony_call.recording.purge_later if @telephony_call.recording.attached?
    @telephony_call.update!(recording_state: 'purged')
    @telephony_call.message&.touch # rubocop:disable Rails/SkipsModelValidations
    head :no_content
  end

  def cancel_transfer
    apply_remote { telephony_client.cancel_transfer(@telephony_call.external_call_id) }
  end

  private

  def apply_remote
    remote = yield
    Telephony::EventApplier.new(account: Current.account).apply_snapshot(remote)
    @telephony_call.reload
    render :show
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Conflict, e.code if e.status == 409
    raise CustomExceptions::Telephony::Invalid, e.code if e.status == 422

    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def fetch_call
    @telephony_call = Telephony::CallProjection.find_by!(account_id: Current.account.id, external_call_id: params[:id])
    authorize @telephony_call, :show?
  end

  # Snapshot del controlador para recuperar la UI tras reconexión (aplica solo versiones nuevas).
  def refresh_from_controller
    remote = telephony_client.call(@telephony_call.external_call_id)
    Telephony::EventApplier.new(account: Current.account).apply_snapshot(remote)
    @telephony_call.reload
  rescue Telephony::ControllerClient::Error => e
    Rails.logger.warn("telephony: no se pudo refrescar #{@telephony_call.external_call_id}: #{e.message}")
  end
end
