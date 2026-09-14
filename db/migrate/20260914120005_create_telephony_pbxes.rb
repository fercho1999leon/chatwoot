class CreateTelephonyPbxes < ActiveRecord::Migration[7.1]
  def change
    # Conexión a la PBX de la cuenta (ARI, SIP WebSocket, TURN, provisioner). Los secretos se
    # guardan en el telephony-controller; aquí solo lo no sensible + estado de sincronización.
    create_table :telephony_pbxes do |t|
      t.references :account, null: false, index: { unique: true }
      t.string :ari_url, null: false, default: ''
      t.string :ari_user, null: false, default: ''
      t.string :ari_app, null: false, default: 'chatwoot'
      t.string :sip_ws_url, null: false, default: ''
      t.string :sip_domain, null: false, default: ''
      t.string :stun_url, null: false, default: ''
      t.string :turn_urls, null: false, default: ''
      t.integer :turn_ttl_seconds, null: false, default: 3600
      t.string :provision_url, null: false, default: ''
      t.string :test_dial, null: false, default: ''
      t.integer :agent_timeout, null: false, default: 30
      t.integer :transfer_timeout, null: false, default: 30
      t.integer :pstn_timeout, null: false, default: 45
      t.integer :max_call_seconds, null: false, default: 3600
      t.boolean :has_ari_password, null: false, default: false
      t.boolean :has_turn_secret, null: false, default: false
      t.boolean :has_provision_token, null: false, default: false
      t.datetime :synced_at
      t.string :sync_error
      t.timestamps
    end
  end
end
