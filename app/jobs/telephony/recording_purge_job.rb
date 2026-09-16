# Purga grabaciones: por retención (todas las cuentas, diario) o a demanda (una cuenta, anteriores a una fecha).
# Cubre las dos ubicaciones: el adjunto en Chatwoot y el archivo que pudo quedar en la PBX sin recoger
# (`stored`/`failed`): marcar `purged` sin borrar allí dejaría audio huérfano en la PBX (M03).
class Telephony::RecordingPurgeJob < ApplicationJob
  queue_as :low

  def perform(account_id: nil, before: nil)
    if account_id
      purge(Telephony::CallProjection.where(account_id: account_id), Time.zone.parse(before.to_s))
    else
      Telephony::Pbx.where('recording_retention_days > 0').find_each do |pbx|
        purge(Telephony::CallProjection.where(account_id: pbx.account_id), pbx.recording_retention_days.days.ago)
      end
    end
  end

  private

  def purge(scope, before)
    return if before.blank?

    old = scope.where(created_at: ...before)
    old.joins(:recording_attachment).find_each { |projection| purge_one(projection) }
    old.where(recording_state: %w[stored failed]).where.not(recording_name: [nil, '']).where.missing(:recording_attachment)
       .find_each { |projection| purge_one(projection) }
  end

  def purge_one(projection)
    projection.recording.purge_later if projection.recording.attached?
    Telephony::RecordingRemote.delete(projection)
    projection.update!(recording_state: 'purged')
    projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
