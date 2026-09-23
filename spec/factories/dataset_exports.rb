# frozen_string_literal: true

FactoryBot.define do
  factory :dataset_export do
    account
    user
    export_format { 'chat_jsonl' }
    status { 'completed' }
    conversations_count { 3 }
  end
end
