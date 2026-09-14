class CreateChannelTelephony < ActiveRecord::Migration[7.1]
  # Inbox de tipo Telephony: configuración de la troncal SIP de la cuenta. El
  # telephony-controller la provisiona en la PBX; el secreto de la troncal vive
  # aquí (como los tokens de otros canales) y se envía al controlador.
  def change
    create_table :channel_telephony do |t|
      t.integer :account_id, null: false
      # custom = Chatwoot escribe la troncal en la PBX; gui = ya existe en FreePBX con nombre trunk_name
      t.string :trunk_mode, null: false, default: 'custom'
      t.string :trunk_name, null: false, default: ''
      add_trunk_columns(t)
      add_policy_columns(t)
      t.timestamps
    end
    add_index :channel_telephony, :account_id
  end

  private

  def add_trunk_columns(t)
    t.string :host, null: false, default: ''
    t.integer :port, null: false, default: 5060
    t.string :transport, null: false, default: 'udp'
    t.string :auth_mode, null: false, default: 'register'
    t.string :username, null: false, default: ''
    t.string :password, null: false, default: ''
    t.jsonb :carrier_ips, null: false, default: []
    t.string :caller_id, null: false, default: ''
    t.jsonb :codecs, null: false, default: %w[ulaw alaw]
    t.string :dtmf, null: false, default: 'rfc4733'
    t.boolean :register, null: false, default: true
  end

  def add_policy_columns(t)
    t.string :default_country, null: false, default: ''
    t.integer :max_call_seconds, null: false, default: 3600
    # Inboxes desde cuyas conversaciones se puede llamar ([] = todos los de la cuenta)
    t.jsonb :allowed_inbox_ids, null: false, default: []
    t.datetime :provisioned_at
    t.string :provision_error
  end
end
