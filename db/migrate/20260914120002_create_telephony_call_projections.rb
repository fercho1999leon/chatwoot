class CreateTelephonyCallProjections < ActiveRecord::Migration[7.1]
  def change
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
    add_index :telephony_call_projections, :conversation_id
  end
end
