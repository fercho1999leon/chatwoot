# Troncal SIP (auditoría 2026-09-25, T2): cómo se marca al carrier y a qué destinos se puede llamar.
#   dial_format: e164 (593987654321, el comportamiento anterior) · e164_plus (+593…) · national (0987654321)
#   dial_prefix: dígitos que se anteponen (prefijo técnico del carrier), '' = ninguno
#   allowed_prefixes: prefijos E.164 permitidos ("593, 1"); '' = el país de default_country; '*' = cualquiera
# max_call_seconds y provisioned_at dejan de usarse (el límite real es el de la conexión PBX y el estado
# de provisión lo da el controlador); se ignoran en el modelo y se borrarán en una migración posterior.
class AddDialPolicyToChannelTelephony < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_telephony, :dial_format, :string, null: false, default: 'e164'
    add_column :channel_telephony, :dial_prefix, :string, null: false, default: ''
    add_column :channel_telephony, :allowed_prefixes, :string, null: false, default: ''
  end
end
