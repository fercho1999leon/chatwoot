# Administración: vincular extensiones de FreePBX a usuarios. El provisioner deja la
# extensión registrable por WebRTC; el secreto vive en el controlador, nunca aquí.
class Api::V1::Accounts::Telephony::EndpointsController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization

  def index
    endpoints = Telephony::Endpoint.where(account_id: Current.account.id).includes(:user)
    render json: endpoints.map { |e| serialize(e) }
  end

  # PUT telephony/endpoints/:user_id { extension: "1001", rotate: false }
  def update
    user = Current.account.users.find(params[:user_id])
    extension = params.require(:extension).to_s
    raise CustomExceptions::Telephony::Invalid, 'invalid_extension' unless extension.match?(/\A\d{2,8}\z/)

    telephony_client.upsert_endpoint(account_id: Current.account.id, user_id: user.id, extension: extension,
                                     display_name: user.name, rotate: ActiveModel::Type::Boolean.new.cast(params[:rotate]))
    record = Telephony::Endpoint.find_or_initialize_by(account_id: Current.account.id, user_id: user.id)
    record.endpoint = extension
    record.enabled = true
    record.save!
    render json: serialize(record)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Conflict, e.code if e.status == 409
    raise CustomExceptions::Telephony::Invalid, e.code if e.status == 422

    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def destroy
    user = Current.account.users.find(params[:user_id])
    telephony_client.delete_endpoint(account_id: Current.account.id, user_id: user.id)
    Telephony::Endpoint.where(account_id: Current.account.id, user_id: user.id).delete_all
    head :no_content
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  private

  def serialize(record)
    { user_id: record.user_id, name: record.user&.name, extension: record.endpoint, enabled: record.enabled }
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
