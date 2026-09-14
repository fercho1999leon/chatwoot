class CreateTelephonyTables < ActiveRecord::Migration[7.1]
  def change
    # Habilitación por inbox (la cuenta se habilita con el feature flag `telephony_calls`).
    create_table :telephony_inbox_settings do |t|
      t.references :account, null: false, index: false
      t.references :inbox, null: false, index: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :telephony_inbox_settings, [:account_id, :inbox_id], unique: true

    # Endpoint PJSIP asignado a un usuario. El secreto vive en el telephony-controller.
    create_table :telephony_endpoints do |t|
      t.references :account, null: false, index: false
      t.references :user, null: false, index: false
      t.string :endpoint, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :telephony_endpoints, [:account_id, :user_id], unique: true
    add_index :telephony_endpoints, :endpoint, unique: true

    # Proyección de la llamada (la verdad vive en el controlador). Una fila por llamada externa.
    create_table :telephony_call_projections do |t|
      t.references :account, null: false, index: false
      t.uuid :external_call_id, null: false
      t.references :user, null: false, index: false
      t.references :conversation, null: false, index: false
      t.references :inbox, index: false
      t.references :message, index: false
      t.string :state, null: false, default: 'requested'
      t.integer :state_version, null: false, default: 0
      t.string :end_reason
      t.string :destination_e164, null: false
      t.datetime :requested_at
      t.datetime :answered_at
      t.datetime :ended_at
      t.integer :duration_seconds
      t.uuid :last_event_id
      t.timestamps
    end
    add_index :telephony_call_projections, [:account_id, :external_call_id], unique: true
    add_index :telephony_call_projections, [:account_id, :user_id, :state]
    add_index :telephony_call_projections, [:conversation_id]

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

    # Replay de callbacks del controlador.
    create_table :telephony_processed_events do |t|
      t.uuid :event_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :telephony_processed_events, :event_id, unique: true
  end
end
