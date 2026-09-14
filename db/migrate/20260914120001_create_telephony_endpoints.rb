class CreateTelephonyEndpoints < ActiveRecord::Migration[7.1]
  def change
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
  end
end
