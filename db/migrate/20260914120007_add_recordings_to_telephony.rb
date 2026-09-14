class AddRecordingsToTelephony < ActiveRecord::Migration[7.1]
  def change
    # Grabación: nombre en la PBX hasta recogerla (ActiveStorage) y estado del proceso.
    add_column :telephony_call_projections, :recording_name, :string
    add_column :telephony_call_projections, :recording_state, :string
    # Retención de grabaciones por cuenta (0 = conservar siempre). El modo de grabación vive en el controlador (PBX).
    add_column :telephony_pbxes, :record_calls, :string, null: false, default: 'never'
    add_column :telephony_pbxes, :recording_retention_days, :integer, null: false, default: 0
  end
end
