class CreateTelephonyRoutingRules < ActiveRecord::Migration[7.1]
  def change
    # Reglas de enrutamiento de llamadas entrantes (ordenadas; la primera que aplica decide cada paso).
    create_table :telephony_routing_rules do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false, default: ''
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :destination, null: false, default: {}
      t.timestamps
    end

    # Entrantes en la proyección: sin agente hasta que alguien contesta.
    change_column_null :telephony_call_projections, :user_id, true
    add_column :telephony_call_projections, :direction, :string, null: false, default: 'outbound'
    add_column :telephony_call_projections, :did, :string
    add_column :telephony_call_projections, :ringing_user_ids, :jsonb, null: false, default: []
    add_column :telephony_call_projections, :answered_by, :string
    add_column :telephony_call_projections, :contact_name, :string
    # Números (DID) de la troncal: identifican la cuenta que atiende cada entrante.
    add_column :channel_telephony, :dids, :string, null: false, default: ''
  end
end
