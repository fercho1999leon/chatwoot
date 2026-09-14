# Conexión de la cuenta a su PBX (solo administradores). Los secretos se envían al
# telephony-controller y nunca se devuelven: la UI recibe '********' si existen.
class Api::V1::Accounts::Telephony::PbxController < Api::V1::Accounts::Telephony::BaseController
  before_action :check_authorization
  before_action :fetch_pbx

  def show
    render json: serialize(@pbx)
  end

  def update
    @pbx.assign_attributes(pbx_params)
    @pbx.save!
    sync!
    render json: serialize(@pbx.reload)
  end

  # Prueba ARI y provisioner con lo que hay en el formulario, sin guardar.
  def test
    candidate = Telephony::Pbx.new(@pbx.attributes.except('id', 'created_at', 'updated_at')).tap { |p| p.assign_attributes(pbx_params) }
    candidate.validate!
    render json: telephony_client.test_pbx(candidate.controller_payload)
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def destroy
    telephony_client.delete_pbx(account_id: Current.account.id) if @pbx.persisted?
    @pbx.destroy! if @pbx.persisted?
    head :no_content
  rescue Telephony::ControllerClient::Error => e
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  private

  def fetch_pbx
    @pbx = Current.account.telephony_pbx || Current.account.build_telephony_pbx
  end

  def pbx_params
    params.require(:pbx).permit(*Telephony::Pbx::EDITABLE_ATTRS, *Telephony::Pbx::SECRET_ATTRS)
  end

  def sync!
    telephony_client.upsert_pbx(@pbx.controller_payload)
    @pbx.update_columns(synced_at: Time.current, sync_error: nil)
  rescue Telephony::ControllerClient::Error => e
    @pbx.update_columns(sync_error: e.code)
    raise CustomExceptions::Telephony::Unavailable, e.code
  end

  def serialize(pbx)
    attrs = pbx.attributes.slice(*Telephony::Pbx::EDITABLE_ATTRS.map(&:to_s), 'synced_at', 'sync_error')
    Telephony::Pbx::SECRET_ATTRS.each { |a| attrs[a.to_s] = pbx.public_send(:"has_#{a}") ? Telephony::Pbx::MASK : '' }
    attrs.merge('configured' => pbx.configured?, 'persisted' => pbx.persisted?)
  end

  def check_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
