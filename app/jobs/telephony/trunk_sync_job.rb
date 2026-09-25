# Envía la troncal al telephony-controller, que la provisiona en la PBX (en diferido).
class Telephony::TrunkSyncJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel::Telephony.find_by(id: channel_id)
    return unless channel&.configured? && Telephony::ControllerClient.configured?

    Telephony::ControllerClient.new.upsert_trunk(channel.controller_payload)
    # El controlador aceptó la troncal; si la PBX la aplica o no lo cuenta GET telephony/status.
    channel.update_columns(provision_error: nil) # rubocop:disable Rails/SkipsModelValidations
  rescue Telephony::ControllerClient::Error => e
    # provision_error = el controlador RECHAZÓ la troncal (did_taken, invalid…): se muestra en la pestaña Telefonía.
    channel.update_columns(provision_error: e.code.to_s.first(250)) # rubocop:disable Rails/SkipsModelValidations
  end
end
