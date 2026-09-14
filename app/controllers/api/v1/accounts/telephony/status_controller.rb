# Estado de la telefonía de la cuenta: PBX/ARI, troncal (provisión, registro, endpoint), agentes registrados.
class Api::V1::Accounts::Telephony::StatusController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def show
    remote = telephony_client.status(account_id: Current.account.id)
    endpoints = Telephony::Endpoint.where(account_id: Current.account.id).includes(:user)
    render json: remote.merge(
      'agents' => endpoints.map do |e|
        { user_id: e.user_id, name: e.user&.name, endpoint: e.endpoint, registered: remote.dig('agents', e.endpoint).to_s == 'Avail' }
      end
    )
  rescue Telephony::ControllerClient::Error => e
    render json: { ari_connected: false, error: e.code, agents: [] }, status: :ok
  end

  private

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
