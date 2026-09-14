class CreateTelephonyCallProjections < ActiveRecord::Migration[7.1]
  # Proyección de la llamada (la verdad vive en el controlador). Una fila por llamada externa.
  def change
    create_table :telephony_call_projections do |t|
      t.references :account, null: false, index: false
      t.uuid :external_call_id, null: false
      t.references :user, null: false, index: false
      t.references :conversation, null: false, index: false
      t.references :inbox, index: false
      t.references :message, index: false
      add_state_columns(t)
      t.timestamps
    end
    add_projection_indexes
  end

  private

  def add_state_columns(t)
    t.string :state, null: false, default: 'requested'
    t.integer :state_version, null: false, default: 0
    t.string :end_reason
    t.string :destination_e164, null: false
    t.datetime :requested_at
    t.datetime :answered_at
    t.datetime :ended_at
    t.integer :duration_seconds
    t.uuid :last_event_id
    t.boolean :on_hold, null: false, default: false
    t.integer :transfer_to_user_id
    t.string :transfer_state
    t.integer :previous_user_id
  end

  def add_projection_indexes
    add_index :telephony_call_projections, [:account_id, :external_call_id], unique: true
    add_index :telephony_call_projections, [:account_id, :user_id, :state]
    add_index :telephony_call_projections, :conversation_id
  end
end
