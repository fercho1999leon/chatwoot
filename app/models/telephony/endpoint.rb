class Telephony::Endpoint < ApplicationRecord
  self.table_name = 'telephony_endpoints'

  belongs_to :account
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :user_id, uniqueness: { scope: :account_id }
end
