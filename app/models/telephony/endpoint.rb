class Telephony::Endpoint < ApplicationRecord
  self.table_name = 'telephony_endpoints'

  belongs_to :account
  belongs_to :user

  # Número de extensión de FreePBX vinculada al usuario (única en la PBX).
  validates :endpoint, presence: true, uniqueness: true, format: { with: /\A\d{2,8}\z/ }
  validates :user_id, uniqueness: { scope: :account_id }
end
