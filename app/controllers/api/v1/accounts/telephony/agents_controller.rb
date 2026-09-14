# Agentes a los que se puede transferir: colaboradores del inbox Telephony con extensión.
class Api::V1::Accounts::Telephony::AgentsController < Api::V1::Accounts::Telephony::BaseController
  def index
    render json: endpoints.map { |e| serialize(e) }
  end

  private

  def endpoints
    Telephony::Endpoint.where(account_id: Current.account.id, enabled: true).where.not(user_id: Current.user.id).includes(:user)
  end

  def busy_ids
    @busy_ids ||= Telephony::CallProjection.active.where(account_id: Current.account.id).pluck(:user_id)
  end

  def availability
    @availability ||= OnlineStatusTracker.get_available_users(Current.account.id) || {}
  end

  def serialize(endpoint)
    { user_id: endpoint.user_id, name: endpoint.user&.name, extension: endpoint.endpoint,
      availability: availability[endpoint.user_id.to_s] || 'offline', busy: busy_ids.include?(endpoint.user_id) }
  end
end
