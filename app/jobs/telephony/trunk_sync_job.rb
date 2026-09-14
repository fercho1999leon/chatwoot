# Envía la troncal al telephony-controller, que la provisiona en la PBX.
class Telephony::TrunkSyncJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel::Telephony.find_by(id: channel_id)
    return unless channel&.configured?
    return unless Telephony::ControllerClient.configured?

    result = Telephony::ControllerClient.new.upsert_trunk(channel.controller_payload)
    provision = result['provision'] || {}
    channel.update_columns(provisioned_at: provision['ok'] ? Time.current : channel.provisioned_at, # rubocop:disable Rails/SkipsModelValidations
                           provision_error: provision['ok'] ? nil : provision['error'].to_s.first(250))
  rescue Telephony::ControllerClient::Error => e
    channel.update_columns(provision_error: e.message.first(250)) # rubocop:disable Rails/SkipsModelValidations
  end
end
