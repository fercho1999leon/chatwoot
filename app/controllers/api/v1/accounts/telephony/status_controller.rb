# Estado de la telefonía de la cuenta: PBX/ARI, troncal (provisión, registro, endpoint), agentes registrados
# y el bloque `health` del controlador (cola hacia Chatwoot, llamadas por estado, patas, grabaciones,
# reconexiones ARI, versión) completado con lo que solo Chatwoot sabe: grabaciones pendientes/fallidas aquí.
class Api::V1::Accounts::Telephony::StatusController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def show
    remote = telephony_client.status(account_id: Current.account.id)
    endpoints = Telephony::Endpoint.where(account_id: Current.account.id).includes(:user)
    render json: remote.merge(
      'agents' => endpoints.map do |e|
        { user_id: e.user_id, name: e.user&.name, endpoint: e.endpoint, registered: remote.dig('agents', e.endpoint).to_s == 'Avail' }
      end,
      'recordings' => local_recordings
    )
  rescue Telephony::ControllerClient::Error => e
    render json: { ari_connected: false, error: e.code, agents: [], recordings: local_recordings }, status: :ok
  end

  private

  # Grabaciones vistas desde Chatwoot: `pending` aún por recoger, `failed` a la espera del barrido horario,
  # `missing` confirmadas como perdidas. Ventana de 7 días: lo anterior ya no se reintenta.
  def local_recordings
    scope = Telephony::CallProjection.where(account_id: Current.account.id, ended_at: 7.days.ago..)
    counts = scope.where(recording_state: %w[stored failed missing]).group(:recording_state).count
    { pending: counts['stored'].to_i, failed: counts['failed'].to_i, missing: counts['missing'].to_i }
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
