class Telephony::InboxSetting < ApplicationRecord
  self.table_name = 'telephony_inbox_settings'

  belongs_to :account
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :account_id }
end
