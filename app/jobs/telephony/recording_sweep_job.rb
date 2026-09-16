# Recolección eventual de grabaciones (M03): cada hora vuelve a encolar la recogida de las que quedaron
# `stored` sin adjuntar (evento perdido, cola parada) o `failed` (la PBX o el controlador no respondían),
# dentro de una ventana: ni recién colgadas (RecordingFetchJob ya está en ello) ni más antiguas que la
# ventana de conservación del archivo en la PBX. Lo que siga sin aparecer termina en `missing` por el 404.
class Telephony::RecordingSweepJob < ApplicationJob
  queue_as :low

  RETRY_AFTER = 10.minutes
  WINDOW = 7.days
  BATCH = 50

  def perform(account_id: nil)
    scope = Telephony::CallProjection
            .where(recording_state: %w[stored failed])
            .where.not(recording_name: [nil, ''])
            .where(ended_at: WINDOW.ago..RETRY_AFTER.ago)
            .where.missing(:recording_attachment)
            .order(ended_at: :desc)
    scope = scope.where(account_id: account_id) if account_id
    scope.limit(BATCH).pluck(:id).each_with_index do |id, i|
      Telephony::RecordingFetchJob.set(wait: (i * 2).seconds).perform_later(id)
    end
  end
end
