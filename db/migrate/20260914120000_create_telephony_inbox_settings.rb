class CreateTelephonyInboxSettings < ActiveRecord::Migration[7.1]
  def change
    # Habilitación por inbox (la cuenta se habilita con el feature flag `telephony_calls`).
    create_table :telephony_inbox_settings do |t|
      t.references :account, null: false, index: false
      t.references :inbox, null: false, index: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :telephony_inbox_settings, [:account_id, :inbox_id], unique: true
  end
end
