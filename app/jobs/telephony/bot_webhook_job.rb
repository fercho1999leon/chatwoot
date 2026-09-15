# Avisa al bot de voz (n8n, etc.) de una entrante recién resuelta. Firma: HMAC-SHA256 del cuerpo con el
# digest del token del bot (Chatwoot solo guarda el SHA256 del token; el receptor lo calcula igual).
# Un solo intento: la llamada no espera; el fallo queda en el log.
class Telephony::BotWebhookJob < ApplicationJob
  queue_as :high

  TIMEOUT = 5
  SIGNATURE_HEADER = 'X-Chatwoot-Telephony-Signature'.freeze

  def perform(projection_id)
    projection = Telephony::CallProjection.find_by(id: projection_id)
    return unless projection

    pbx = projection.account.telephony_pbx
    return if pbx.nil? || pbx.bot_webhook_url.blank?

    deliver(pbx, projection)
  end

  private

  def deliver(pbx, projection)
    body = Telephony::BotCallContext.new(projection: projection).webhook_payload.to_json
    response = HTTParty.post(pbx.bot_webhook_url, body: body, timeout: TIMEOUT,
                                                  headers: { 'Content-Type' => 'application/json', SIGNATURE_HEADER => signature(pbx, body) })
    Rails.logger.warn("telephony: webhook del bot respondió #{response.code} (#{projection.external_call_id})") unless response.success?
  rescue *Telephony::ControllerClient::NETWORK_ERRORS, HTTParty::Error, OpenSSL::SSL::SSLError => e
    Rails.logger.warn("telephony: webhook del bot falló (#{projection.external_call_id}): #{e.class}")
  end

  def signature(pbx, body)
    OpenSSL::HMAC.hexdigest('SHA256', pbx.bot_token_digest.to_s, body)
  end
end
