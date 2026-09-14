class CreateTelephonyIdempotencyKeys < ActiveRecord::Migration[7.1]
  def change
    # Idempotencia de POST telephony_calls: misma clave + mismo payload → misma llamada.
    create_table :telephony_idempotency_keys do |t|
      t.references :account, null: false, index: false
      t.references :user, null: false, index: false
      t.string :key, null: false
      t.string :payload_hash, null: false
      t.uuid :call_id, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :telephony_idempotency_keys, [:account_id, :user_id, :key], unique: true, name: 'index_telephony_idem_on_account_user_key'
  end
end
