class Api::V1::Accounts::Conversations::TelephonyCallsController < Api::V1::Accounts::Conversations::BaseController
  rescue_from CustomExceptions::Telephony::Conflict, CustomExceptions::Telephony::Invalid,
              CustomExceptions::Telephony::Unavailable, with: :render_telephony_error

  def create
    @telephony_call, created = Telephony::CallCreator.new(
      account: Current.account, user: Current.user, conversation: @conversation,
      idempotency_key: request.headers['Idempotency-Key']
    ).perform
    render :show, status: created ? :created : :ok
  end

  private

  def render_telephony_error(exception)
    render json: { error: exception.message, code: exception.message }, status: exception.http_status
  end
end
