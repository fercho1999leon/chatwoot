class Api::V1::Accounts::DatasetExportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_dataset_export, only: [:destroy]

  def index
    @dataset_exports = Current.account.dataset_exports.includes(:user, file_attachment: :blob).latest_first
  end

  def destroy
    @dataset_export.destroy!
    head :ok
  end

  private

  def check_authorization
    authorize Conversation, :export_dataset?
  end

  def fetch_dataset_export
    @dataset_export = Current.account.dataset_exports.find(params[:id])
  end
end
