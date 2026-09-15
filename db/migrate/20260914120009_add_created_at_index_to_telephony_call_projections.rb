class AddCreatedAtIndexToTelephonyCallProjections < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Historial (página Calls) ordena y filtra por fecha dentro de la cuenta.
    add_index :telephony_call_projections, [:account_id, :created_at], algorithm: :concurrently
    add_index :telephony_processed_events, :created_at, algorithm: :concurrently
    add_index :telephony_idempotency_keys, :expires_at, algorithm: :concurrently
  end
end
