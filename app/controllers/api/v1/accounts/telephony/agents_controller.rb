# Agentes a los que se puede transferir: colaboradores del inbox Telephony con extensión.
class Api::V1::Accounts::Telephony::AgentsController < Api::V1::Accounts::Telephony::BaseController
  def index
    endpoints = Telephony::Endpoint.where(account_id: Current.account.id, enabled: true).where.not(user_id: Current.user.id).includes(:user)
    busy_ids = Telephony::CallProjection.active.where(account_id: Current.account.id).pluck(:user_id)
    availability = OnlineStatusTracker.get_available_users(Current.account.id) || {}
    render json: endpoints.map do |e|
      { user_id: e.user_id, name: e.user&.name, endpoint: e.endpoint,
        availability: availability[e.user_id.to_s] || 'offline', busy: busy_ids.include?(e.user_id) }
    end
  end
end
