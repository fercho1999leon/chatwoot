# Recoge la grabación de la PBX (vía controlador), la guarda en ActiveStorage y la borra de la PBX.
class Telephony::RecordingFetchJob < ApplicationJob
  queue_as :low
  retry_on Telephony::ControllerClient::Error, wait: 30.seconds, attempts: 5

  def perform(projection_id)
    projection = Telephony::CallProjection.find_by(id: projection_id)
    return unless projection&.recording_name.present? && projection.recording_state == 'stored'
    return if projection.recording.attached?

    Tempfile.create(['telephony-recording', '.wav']) do |tmp|
      content_type = Telephony::ControllerClient.new.download_recording(projection.external_call_id, to: tmp.path)
      tmp.rewind
      projection.recording.attach(io: File.open(tmp.path), filename: "call-#{projection.external_call_id[0, 8]}.wav",
                                  content_type: content_type.presence || 'audio/wav')
    end
    projection.update!(recording_state: 'fetched')
    Telephony::ControllerClient.new.delete_recording(projection.external_call_id)
    # Rebroadcast the card so the player appears without a refetch.
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
