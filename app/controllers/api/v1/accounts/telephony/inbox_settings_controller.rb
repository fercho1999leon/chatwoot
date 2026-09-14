# Administración: habilitar telefonía por inbox.
class Api::V1::Accounts::Telephony::InboxSettingsController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def index
    render json: Telephony::InboxSetting.where(account_id: Current.account.id).map { |s| { inbox_id: s.inbox_id, enabled: s.enabled } }
  end

  def update
    inbox = Current.account.inboxes.find(params[:inbox_id])
    setting = Telephony::InboxSetting.find_or_initialize_by(account_id: Current.account.id, inbox_id: inbox.id)
    setting.enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
    setting.save!
    render json: { inbox_id: inbox.id, enabled: setting.enabled }
  end

  private

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
