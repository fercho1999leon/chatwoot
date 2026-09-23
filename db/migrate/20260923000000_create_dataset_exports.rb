class CreateDatasetExports < ActiveRecord::Migration[7.1]
  def change
    create_table :dataset_exports do |t|
      t.references :account, null: false, index: true
      t.references :user, null: false, index: true
      t.string :export_format, null: false
      t.jsonb :params, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.integer :conversations_count
      t.text :error_message

      t.timestamps
    end

    add_index :dataset_exports, [:account_id, :created_at]
  end
end
