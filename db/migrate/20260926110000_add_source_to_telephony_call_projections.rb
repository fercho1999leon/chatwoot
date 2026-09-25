# Llamadas que enruta FreePBX y el telephony-controller solo observa (source = 'pbx'): el softphone las controla
# por SIP (espera por re-INVITE, transferencia por REFER, DTMF) en vez de por la API del controlador.
class AddSourceToTelephonyCallProjections < ActiveRecord::Migration[7.1]
  def change
    add_column :telephony_call_projections, :source, :string, null: false, default: 'controller'
  end
end
