# El inbox de Telefonía se borró: el controlador retira la troncal de la PBX (endpoint, registro,
# Inbound Routes de sus DIDs e IPs del firewall). Sin esto seguía registrada en el carrier.
class Telephony::TrunkRemoveJob < ApplicationJob
  queue_as :default
  retry_on Telephony::ControllerClient::Error, wait: :polynomially_longer, attempts: 5

  def perform(account_id)
    return unless Telephony::ControllerClient.configured?
    # Un inbox nuevo de la misma cuenta ya ocupó su lugar: su TrunkSyncJob manda la troncal vigente.
    return if Channel::Telephony.exists?(account_id: account_id)

    Telephony::ControllerClient.new.delete_trunk(account_id: account_id)
  end
end
