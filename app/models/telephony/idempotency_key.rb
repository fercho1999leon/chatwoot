# == Schema Information
#
# Table name: telephony_idempotency_keys
#
#  id           :bigint           not null, primary key
#  expires_at   :datetime         not null
#  key          :string           not null
#  payload_hash :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  call_id      :uuid             not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_telephony_idem_on_account_user_key  (account_id,user_id,key) UNIQUE
#
class Telephony::IdempotencyKey < ApplicationRecord
  self.table_name = 'telephony_idempotency_keys'

  belongs_to :account
  belongs_to :user

  validates :key, presence: true, uniqueness: { scope: [:account_id, :user_id] }
end
