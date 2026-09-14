class CreateTelephonyPbxes < ActiveRecord::Migration[7.1]
  STRINGS = { ari_url: '', ari_user: '', ari_app: 'chatwoot', sip_ws_url: '', sip_domain: '', stun_url: '',
              turn_urls: '', provision_url: '', test_dial: '' }.freeze
  INTEGERS = { turn_ttl_seconds: 3600, agent_timeout: 30, transfer_timeout: 30, pstn_timeout: 45, max_call_seconds: 3600 }.freeze
  FLAGS = %i[has_ari_password has_turn_secret has_provision_token].freeze

  def change
    # Conexión a la PBX de la cuenta (ARI, SIP WebSocket, TURN, provisioner). Los secretos se
    # guardan en el telephony-controller; aquí solo lo no sensible + estado de sincronización.
    create_table :telephony_pbxes do |t|
      t.references :account, null: false, index: { unique: true }
      STRINGS.each { |name, default| t.string name, null: false, default: default }
      INTEGERS.each { |name, default| t.integer name, null: false, default: default }
      FLAGS.each { |name| t.boolean name, null: false, default: false }
      t.datetime :synced_at
      t.string :sync_error
      t.timestamps
    end
  end
end
