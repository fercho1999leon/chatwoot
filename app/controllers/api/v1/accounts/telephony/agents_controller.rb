# Agentes a los que se puede transferir: usuarios de la cuenta con extensión vinculada.
# Con conversation_id indica si cada uno es colaborador del inbox de esa conversación
# (si no lo es, no verá la conversación al recibir la llamada).
class Api::V1::Accounts::Telephony::AgentsController < Api::V1::Accounts::Telephony::BaseController
  def index
    render json: {
      can_add_members: Current.account_user.administrator?,
      inbox_id: conversation&.inbox_id,
      agents: endpoints.map { |e| serialize(e) }
    }
  end

  private

  def conversation
    return nil if params[:conversation_id].blank?

    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id])
  end

  def endpoints
    Telephony::Endpoint.where(account_id: Current.account.id, enabled: true).where.not(user_id: Current.user.id).includes(:user)
  end

  def busy_ids
    @busy_ids ||= Telephony::CallProjection.active.where(account_id: Current.account.id).pluck(:user_id)
  end

  def availability
    @availability ||= OnlineStatusTracker.get_available_users(Current.account.id) || {}
  end

  def member_ids
    @member_ids ||= conversation ? conversation.inbox.inbox_members.pluck(:user_id) : nil
  end

  def serialize(endpoint)
    { user_id: endpoint.user_id, name: endpoint.user&.name, extension: endpoint.endpoint,
      availability: availability[endpoint.user_id.to_s] || 'offline', busy: busy_ids.include?(endpoint.user_id),
      inbox_member: member_ids.nil? || member_ids.include?(endpoint.user_id) }
  end
end
