# Modelo «Asterisk enruta, Chatwoot atiende»: la troncal del carrier es una troncal nativa de FreePBX creada desde
# Chatwoot (native) o una que ya existe en FreePBX (existing). En los dos casos la saliente va por las Outbound Routes.
#   custom → native · gui/routes → existing
class NativeTrunkModesForChannelTelephony < ActiveRecord::Migration[7.1]
  def up
    change_column_default :channel_telephony, :trunk_mode, from: 'custom', to: 'native'
    execute "UPDATE channel_telephony SET trunk_mode = 'native' WHERE trunk_mode = 'custom'"
    execute "UPDATE channel_telephony SET trunk_mode = 'existing' WHERE trunk_mode IN ('gui', 'routes')"
  end

  def down
    change_column_default :channel_telephony, :trunk_mode, from: 'native', to: 'custom'
    execute "UPDATE channel_telephony SET trunk_mode = 'custom' WHERE trunk_mode = 'native'"
    execute "UPDATE channel_telephony SET trunk_mode = 'routes' WHERE trunk_mode = 'existing'"
  end
end
