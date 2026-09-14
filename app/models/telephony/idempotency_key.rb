class Telephony::IdempotencyKey < ApplicationRecord
  self.table_name = 'telephony_idempotency_keys'

  belongs_to :account
  belongs_to :user

  validates :key, presence: true, uniqueness: { scope: [:account_id, :user_id] }
end
