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

  def add_state_columns(table)
    table.string :state, null: false, default: 'requested'
    table.integer :state_version, null: false, default: 0
    table.string :end_reason
    table.string :destination_e164, null: false
    table.datetime :requested_at
    table.datetime :answered_at
    table.datetime :ended_at
    table.integer :duration_seconds
    table.uuid :last_event_id
    table.boolean :on_hold, null: false, default: false
    table.integer :transfer_to_user_id
    table.string :transfer_state
    table.integer :previous_user_id
  end

  def add_projection_indexes
    add_index :telephony_call_projections, [:account_id, :external_call_id], unique: true
    add_index :telephony_call_projections, [:account_id, :user_id, :state]
    add_index :telephony_call_projections, :conversation_id
  end
end
