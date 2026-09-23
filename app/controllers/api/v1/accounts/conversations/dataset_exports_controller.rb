class Api::V1::Accounts::Conversations::DatasetExportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def create
    return render_could_not_create_error(I18n.t('errors.conversations.export_dataset.invalid_params')) unless valid_params?

    Account::ConversationsDatasetExportJob.perform_later(Current.account.id, Current.user.id, export_params)
    head :ok, message: I18n.t('errors.conversations.export_dataset.success')
  end

  def preview
    return render_could_not_create_error(I18n.t('errors.conversations.export_dataset.invalid_params')) unless valid_params?

    render json: Conversations::DatasetPreview.new(Current.account, Current.user, export_params.with_indifferent_access).perform
  end

  private

  def check_authorization
    authorize Conversation, :export_dataset?
  end

  def export_params
    permitted = params.permit(
      :export_format, :status, :since, :until, :limit,
      inbox_ids: [],
      options: [:anonymize, :include_private_notes, :include_bot_messages, :min_agent_messages,
                :min_user_messages, :min_csat, :system_prompt, :eval_ratio]
    )
    permitted.to_h.merge(payload: params.permit!['payload'])
  end

  def valid_params?
    Account::ConversationsDatasetExportJob::FORMATS.include?(params[:export_format]) &&
      (params[:limit].blank? || params[:limit].to_i.positive?) &&
      (params[:status].blank? || Conversation.statuses.key?(params[:status]))
  end
end
