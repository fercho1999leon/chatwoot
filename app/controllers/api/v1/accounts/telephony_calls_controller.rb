class Api::V1::Accounts::TelephonyCallsController < Api::V1::Accounts::Telephony::BaseController
  before_action :fetch_call, only: [:show, :hangup, :dtmf, :hold, :unhold, :transfer, :cancel_transfer]

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

  def hold
    apply_remote { telephony_client.hold(@telephony_call.external_call_id, hold: true) }
  end

  def unhold
    apply_remote { telephony_client.hold(@telephony_call.external_call_id, hold: false) }
  end

  def transfer
    to_user = Current.account.users.find(params.require(:to_user_id))
    raise CustomExceptions::Telephony::Invalid, 'no_endpoint' unless Telephony::Endpoint.exists?(account_id: Current.account.id, user_id: to_user.id, enabled: true)

    apply_remote { telephony_client.transfer(@telephony_call.external_call_id, to_user_id: to_user.id) }
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
