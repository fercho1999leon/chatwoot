class Api::V1::Accounts::Telephony::CapabilitiesController < Api::V1::Accounts::Telephony::BaseController
  def show
    conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize conversation, :show?
    render json: Telephony::CapabilityResolver.new(account: Current.account, user: Current.user, conversation: conversation).resolve
  end
end
