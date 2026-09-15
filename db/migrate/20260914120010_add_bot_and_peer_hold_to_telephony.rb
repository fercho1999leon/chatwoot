class AddBotAndPeerHoldToTelephony < ActiveRecord::Migration[7.1]
  def change
    # API del bot de voz: token por cuenta (solo el digest) y webhook opcional al resolver una entrante.
    add_column :telephony_pbxes, :bot_token_digest, :string
    add_column :telephony_pbxes, :bot_webhook_url, :string, null: false, default: ''
    add_index :telephony_pbxes, :bot_token_digest, unique: true
    # Cliente en espera (hold remoto), quién reenrutó la llamada ('bot') y pista del dialplan (CHATWOOT_HINT).
    add_column :telephony_call_projections, :peer_on_hold, :boolean, null: false, default: false
    add_column :telephony_call_projections, :routed_by, :string
    add_column :telephony_call_projections, :hint, :string
  end
end
