# Limpieza diaria de tablas auxiliares de telefonía que crecen sin límite:
# claves de idempotencia caducadas y el registro de eventos ya procesados (dedupe del webhook).
class Telephony::HousekeepingJob < ApplicationJob
  queue_as :low

  PROCESSED_EVENTS_RETENTION = 7.days

  def perform
    Telephony::IdempotencyKey.where(expires_at: ...Time.current).in_batches(&:delete_all)
    Telephony::ProcessedEvent.where(created_at: ...PROCESSED_EVENTS_RETENTION.ago).in_batches(&:delete_all)
  end
end
