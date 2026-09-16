# API del bot de voz (IA en una extensión, n8n…): contexto de una entrante y a quién devolverla.
# `:id` es el external_call_id (UUID). Autenticación por token de cuenta (TelephonyBotAuthenticatable).
class Api::V1::Telephony::Bot::CallsController < ActionController::API
  include TelephonyBotAuthenticatable

  DEFAULT_TIMEOUT = 20

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from CustomExceptions::Telephony::Conflict, CustomExceptions::Telephony::Invalid,
              CustomExceptions::Telephony::Unavailable, with: :render_telephony_error

  before_action :fetch_call

  def show
    render json: Telephony::BotCallContext.new(projection: @projection).payload
  end

  # POST bot/calls/:id/route { target: {type, team_id|user_ids|user_id|number|extension}, timeout?, note? }
  #
  # Idempotente (H13): la clave es `Idempotency-Key` (cabecera) o `request_id` (cuerpo); sin ninguna, el hash del
  # propio comando. Repetir la misma clave (reintento de n8n, doble tool-call de la IA) devuelve la respuesta
  # original sin volver a desmontar/timbrar ni duplicar la nota; el controlador la guarda también (`reroute_key`).
  def route
    cached = Rails.cache.read(idempotency_cache_key)
    return render json: cached if cached

    steps = planner.steps_for_target(target_params, timeout: params[:timeout].presence || DEFAULT_TIMEOUT)
    raise CustomExceptions::Telephony::Invalid, 'no_agents_online' if steps.empty?

    reroute!(steps)
    add_private_note(params[:note]) if params[:note].present?
    body = { ok: true, steps: steps, request_id: idempotency_key }
    Rails.cache.write(idempotency_cache_key, body, expires_in: IDEMPOTENCY_TTL)
    render json: body
  end

  private

  IDEMPOTENCY_TTL = 15.minutes

  def idempotency_key
    @idempotency_key ||= begin
      given = request.headers['Idempotency-Key'].presence || params[:request_id].presence
      given ? given.to_s.first(128) : Digest::SHA256.hexdigest([target_params.to_h.sort.to_h, params[:timeout], params[:note]].to_json)
    end
  end

  def idempotency_cache_key
    "telephony:bot_route:#{@account.id}:#{@projection.external_call_id}:#{idempotency_key}"
  end

  def reroute!(steps)
    remote = telephony_client.reroute(@projection.external_call_id, steps: steps, by: 'bot', note: params[:note].presence, key: idempotency_key)
    Telephony::EventApplier.new(account: @account).apply_snapshot(remote)
  rescue Telephony::ControllerClient::Error => e
    raise_for(e)
  end

  def raise_for(error)
    case error.status
    when 409 then raise CustomExceptions::Telephony::Conflict, error.code
    when 422 then raise CustomExceptions::Telephony::Invalid, error.code
    when 404 then raise ActiveRecord::RecordNotFound
    else raise CustomExceptions::Telephony::Unavailable, error.code
    end
  end

  def fetch_call
    @projection = Telephony::CallProjection.find_by!(account_id: @account.id, external_call_id: params[:id])
  end

  def target_params
    params.require(:target).permit(:type, :team_id, :user_id, :number, :extension, user_ids: []).to_h
  end

  def planner
    Telephony::RoutingPlanner.new(account: @account, conversation: @projection.conversation, contact: @projection.conversation&.contact,
                                  did: @projection.did.to_s, caller_e164: @projection.destination_e164, hint: @projection.hint)
  end

  # Resumen del bot para el agente que conteste: nota privada, nunca sale por el canal del cliente.
  def add_private_note(note)
    conversation = @projection.conversation
    return unless conversation

    conversation.messages.create!(account: @account, inbox: conversation.inbox, message_type: :outgoing, private: true,
                                  content: note.to_s.first(10_000), sender: nil)
  end

  def telephony_client
    @telephony_client ||= Telephony::ControllerClient.new
  end

  def render_not_found
    render json: { error: 'not_found' }, status: :not_found
  end

  def render_telephony_error(exception)
    render json: { error: exception.message, code: exception.message }, status: exception.http_status
  end
end
