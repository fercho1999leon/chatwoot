# Una troncal SIP por cuenta: el telephony-controller guarda una sola (trunk-<account_id>) y
# CapabilityResolver / InboundResolver leen el primer inbox de Telefonía. Un segundo inbox
# sobrescribía la troncal en la PBX mientras Chatwoot seguía leyendo el primero.
class UniqueTelephonyChannelPerAccount < ActiveRecord::Migration[7.1]
  def change
    remove_index :channel_telephony, :account_id, name: 'index_channel_telephony_on_account_id'
    add_index :channel_telephony, :account_id, unique: true, name: 'index_channel_telephony_on_account_id'
  end
end
