class Api::V1::Accounts::Telephony::BaseController < Api::V1::Accounts::BaseController
  rescue_from CustomExceptions::Telephony::Conflict, CustomExceptions::Telephony::Invalid,
              CustomExceptions::Telephony::Unavailable, with: :render_telephony_error

  private

  def render_telephony_error(exception)
    render json: { error: exception.message, code: exception.message }, status: exception.http_status
  end

  def telephony_client
    @telephony_client ||= Telephony::ControllerClient.new
  end
end
