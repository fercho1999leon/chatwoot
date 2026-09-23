class Api::V1::Accounts::DatasetExportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    @dataset_exports = Current.account.dataset_exports.includes(:user, file_attachment: :blob).latest_first
  end

  private

  def check_authorization
    authorize Conversation, :export_dataset?
  end
end
