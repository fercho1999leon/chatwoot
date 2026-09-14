class Api::V1::Accounts::TelephonyCallsController < Api::V1::Accounts::Telephony::BaseController
  before_action :fetch_call, only: [:show, :hangup, :dtmf]

  def active
    @telephony_call = Telephony::CallProjection.active.find_by(account_id: Current.account.id, user_id: Current.user.id)
    return render json: nil unless @telephony_call

    refresh_from_controller
    render :show
  end

  def show
    refresh_from_controller unless @telephony_call.ended?
    render :show
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

  private

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
