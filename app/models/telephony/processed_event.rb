# == Schema Information
#
# Table name: telephony_processed_events
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  event_id   :uuid             not null
#
# Indexes
#
#  index_telephony_processed_events_on_event_id  (event_id) UNIQUE
#
class Telephony::ProcessedEvent < ApplicationRecord
  self.table_name = 'telephony_processed_events'
end
