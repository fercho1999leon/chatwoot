# == Schema Information
#
# Table name: dataset_exports
#
#  id                  :bigint           not null, primary key
#  conversations_count :integer
#  error_message       :text
#  export_format       :string           not null
#  params              :jsonb            not null
#  status              :integer          default("processing"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  user_id             :bigint           not null
#
# Indexes
#
#  index_dataset_exports_on_account_id                 (account_id)
#  index_dataset_exports_on_account_id_and_created_at  (account_id,created_at)
#  index_dataset_exports_on_user_id                    (user_id)
#
class DatasetExport < ApplicationRecord
  belongs_to :account
  belongs_to :user

  has_one_attached :file

  enum status: { processing: 0, completed: 1, failed: 2 }

  scope :latest_first, -> { order(created_at: :desc) }

  def file_url
    return unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(file)
  end
end
