# == Schema Information
#
# Table name: telephony_endpoints
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  endpoint   :string           not null
#  webrtc     :boolean          default(TRUE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_telephony_endpoints_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#  index_telephony_endpoints_on_endpoint                (endpoint) UNIQUE
#
class Telephony::Endpoint < ApplicationRecord
  self.table_name = 'telephony_endpoints'

  belongs_to :account
  belongs_to :user

  # Número de extensión de FreePBX vinculada al usuario (única en la PBX). webrtc = false: la registra otro
  # equipo (agente de voz IA, teléfono físico); se observa igual pero el navegador no tiene softphone.
  validates :endpoint, presence: true, uniqueness: true, format: { with: /\A\d{2,8}\z/ }
  validates :user_id, uniqueness: { scope: :account_id }
end
