# Destinos de FreePBX (extensiones, colas, ring groups) a los que el agente puede transferir por REFER una llamada
# que enruta FreePBX. Lo usa cualquier agente con extensión: es su teléfono, no la configuración de la PBX.
class Api::V1::Accounts::Telephony::TransferTargetsController < Api::V1::Accounts::Telephony::BaseController
  def index
    endpoint = Telephony::Endpoint.exists?(account_id: Current.account.id, user_id: Current.user.id, enabled: true)
    raise CustomExceptions::Telephony::Invalid, 'no_endpoint' unless endpoint

    render json: telephony_client.transfer_targets(account_id: Current.account.id)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end
end
