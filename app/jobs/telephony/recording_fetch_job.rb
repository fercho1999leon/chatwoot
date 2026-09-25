# Recoge la grabación de la PBX (vía controlador), la guarda en ActiveStorage y la borra de la PBX.
# Idempotente: si ya está adjunta solo intenta el borrado remoto pendiente.
#
# Estados de `recording_state` (M03: captura, recogida y borrado son independientes y durables):
#   stored  → anunciada por el controlador, sin recoger todavía (la tarjeta dice «procesando»)
#   fetched → adjunta en Chatwoot y borrada de la PBX
#   failed  → los reintentos de esta pasada se agotaron; Telephony::RecordingSweepJob la vuelve a intentar
#   missing → la PBX confirmó que el archivo no existe: terminal, nadie la busca más
#   purged  → borrada por retención o a mano: terminal
class Telephony::RecordingFetchJob < ApplicationJob
  queue_as :low
  TERMINAL_STATES = %w[fetched missing purged].freeze

  # Tras agotar los reintentos la tarjeta deja de decir "procesando"; el barrido horario lo reintenta más tarde.
  retry_on Telephony::ControllerClient::Error, wait: 30.seconds, attempts: 5 do |job, _error|
    projection = Telephony::CallProjection.find_by(id: job.arguments.first)
    next unless projection && projection.recording_state == 'stored'

    projection.update!(recording_state: 'failed')
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end

  def perform(projection_id)
    projection = Telephony::CallProjection.find_by(id: projection_id)
    return if projection&.recording_name.blank?
    return if TERMINAL_STATES.include?(projection.recording_state)

    collect(projection)
  rescue RecordingGone
    # 404 del controlador (ya no está `stored` allí) o de la PBX: no hay nada que recoger.
    projection.update!(recording_state: 'missing')
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end

  class RecordingGone < StandardError; end

  private

  def collect(projection)
    attach!(projection) unless projection.recording.attached?
    delete_remote(projection)
    projection.update!(recording_state: 'fetched') unless projection.recording_state == 'fetched'
  end

  # Las grabaciones de FreePBX (llamadas que enruta él) pueden venir en mp3 u ogg según su ajuste de formato.
  EXTENSIONS = { 'audio/mpeg' => '.mp3', 'audio/ogg' => '.ogg' }.freeze

  def attach!(projection)
    Tempfile.create(['telephony-recording', '.audio']) do |tmp|
      content_type = Telephony::ControllerClient.new.download_recording(projection.external_call_id, to: tmp.path).presence || 'audio/wav'
      filename = "call-#{projection.external_call_id[0, 8]}#{EXTENSIONS.fetch(content_type, '.wav')}"
      projection.recording.attach(io: File.open(tmp.path), filename: filename, content_type: content_type)
    end
    # Rebroadcast the card so the player appears without a refetch.
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  rescue Telephony::ControllerClient::Error => e
    raise RecordingGone if e.status == 404 || e.code == 'pbx_recording_404'

    raise e
  end

  def delete_remote(projection)
    Telephony::ControllerClient.new.delete_recording(projection.external_call_id)
  rescue Telephony::ControllerClient::Error => e
    raise e unless e.status == 404 # ya no está en la PBX
  end
end
