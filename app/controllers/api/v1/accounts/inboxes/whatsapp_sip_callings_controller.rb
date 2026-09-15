# WhatsApp Business Calling por SIP (CE): activa/desactiva en Meta y provisiona la troncal en la PBX.
class Api::V1::Accounts::Inboxes::WhatsappSipCallingsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :check_authorization
  before_action :ensure_whatsapp_cloud

  def show
    render json: { config: service.current_config, remote: safe_remote_status }
  end

  def create
    config = params[:resync].present? ? service.resync! : service.enable!(hostname: params.require(:hostname))
    render json: { config: config }
  rescue Whatsapp::SipCallingService::Error, Telephony::ControllerClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def destroy
    render json: { config: service.disable! }
  rescue Whatsapp::SipCallingService::Error, Telephony::ControllerClient::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def check_authorization
    authorize @inbox, :update?
  end

  def ensure_whatsapp_cloud
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.voice_calling_supported?

    render json: { error: 'not_whatsapp_cloud' }, status: :unprocessable_content
  end

  def service
    @service ||= Whatsapp::SipCallingService.new(channel: @inbox.channel)
  end

  def safe_remote_status
    service.remote_status
  rescue Whatsapp::SipCallingService::Error => e
    { error: e.message }
  end
end
