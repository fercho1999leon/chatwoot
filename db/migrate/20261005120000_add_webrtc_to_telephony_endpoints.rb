# Extensiones vinculadas sin WebRTC: el agente de voz IA o un teléfono físico se registran por su cuenta en
# FreePBX. Se observan igual (tarjeta, conversación, grabación), pero Chatwoot no prepara la extensión para el
# navegador ni le ofrece softphone.
class AddWebrtcToTelephonyEndpoints < ActiveRecord::Migration[7.1]
  def change
    add_column :telephony_endpoints, :webrtc, :boolean, null: false, default: true
  end
end
