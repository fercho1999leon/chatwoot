# Purga grabaciones: por retención (todas las cuentas, diario) o a demanda (una cuenta, anteriores a una fecha).
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

    scope.where(created_at: ...before).joins(:recording_attachment).find_each do |projection|
      projection.recording.purge_later
      projection.update!(recording_state: 'purged')
      projection.message&.touch # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
