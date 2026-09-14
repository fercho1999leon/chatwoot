# Administración: asignar un endpoint SIP a un usuario. El secreto se genera aquí,
# se entrega al controlador (que lo guarda y lo servirá solo al dueño) y se devuelve
# UNA vez para cargarlo en la PBX hasta que exista provisión automática (Fase 5).
class Api::V1::Accounts::Telephony::EndpointsController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def index
    endpoints = Telephony::Endpoint.where(account_id: Current.account.id)
    render json: endpoints.map { |e| { user_id: e.user_id, endpoint: e.endpoint, enabled: e.enabled } }
  end

  def update
    user = Current.account.users.find(params[:user_id])
    record = build_record(user)
    secret = params[:secret].presence || SecureRandom.hex(16)
    push_to_controller(record, user, secret)
    record.save!
    render json: { user_id: user.id, endpoint: record.endpoint, enabled: record.enabled, secret: secret }
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  private

  def build_record(user)
    record = Telephony::Endpoint.find_or_initialize_by(account_id: Current.account.id, user_id: user.id)
    record.endpoint = params[:endpoint].presence || "agent-#{user.id}"
    record.enabled = params.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(params[:enabled]) : true
    record
  end

  def push_to_controller(record, user, secret)
    telephony_client.upsert_endpoint(account_id: Current.account.id, user_id: user.id, endpoint: record.endpoint,
                                     secret: secret, display_name: user.name, enabled: record.enabled)
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
