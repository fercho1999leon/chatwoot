# Envía la troncal al telephony-controller, que la provisiona en la PBX.
class Telephony::TrunkSyncJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel::Telephony.find_by(id: channel_id)
    return unless channel&.configured? && Telephony::ControllerClient.configured?

    result = Telephony::ControllerClient.new.upsert_trunk(channel.controller_payload)
    record_result(channel, result['provision'] || {})
  rescue Telephony::ControllerClient::Error => e
    channel.update_columns(provision_error: e.message.first(250)) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def record_result(channel, provision)
    if provision['ok']
      channel.update_columns(provisioned_at: Time.current, provision_error: nil) # rubocop:disable Rails/SkipsModelValidations
    else
      channel.update_columns(provision_error: provision['error'].to_s.first(250)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
