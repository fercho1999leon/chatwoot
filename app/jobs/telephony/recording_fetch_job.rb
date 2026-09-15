# Recoge la grabación de la PBX (vía controlador), la guarda en ActiveStorage y la borra de la PBX.
# Idempotente: si ya está adjunta solo intenta el borrado remoto pendiente.
class Telephony::RecordingFetchJob < ApplicationJob
  queue_as :low
  # Tras agotar los reintentos la tarjeta deja de decir "procesando" y muestra que no hay grabación.
  retry_on Telephony::ControllerClient::Error, wait: 30.seconds, attempts: 5 do |job, _error|
    projection = Telephony::CallProjection.find_by(id: job.arguments.first)
    next unless projection && projection.recording_state == 'stored'

    projection.update!(recording_state: 'failed')
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end

  def perform(projection_id)
    projection = Telephony::CallProjection.find_by(id: projection_id)
    return if projection&.recording_name.blank?
    return if projection.recording_state == 'purged'

    attach!(projection) unless projection.recording.attached?
    delete_remote(projection)
    projection.update!(recording_state: 'fetched') unless projection.recording_state == 'fetched'
  end

  private

  def attach!(projection)
    Tempfile.create(['telephony-recording', '.wav']) do |tmp|
      content_type = Telephony::ControllerClient.new.download_recording(projection.external_call_id, to: tmp.path)
      projection.recording.attach(io: File.open(tmp.path), filename: "call-#{projection.external_call_id[0, 8]}.wav",
                                  content_type: content_type.presence || 'audio/wav')
    end
    # Rebroadcast the card so the player appears without a refetch.
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end

  def delete_remote(projection)
    Telephony::ControllerClient.new.delete_recording(projection.external_call_id)
  rescue Telephony::ControllerClient::Error => e
    raise e unless e.status == 404 # ya no está en la PBX
  end
end
