class CreateTelephonyProcessedEvents < ActiveRecord::Migration[7.1]
  def change
    # Replay de callbacks del controlador.
    create_table :telephony_processed_events do |t|
      t.uuid :event_id, null: false
      t.datetime :created_at, null: false
    end
    add_index :telephony_processed_events, :event_id, unique: true
  end
end
