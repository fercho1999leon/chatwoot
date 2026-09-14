# frozen_string_literal: true

class CustomExceptions::Telephony::Conflict < CustomExceptions::Base
  # @data es el código: agent_busy | idempotency_mismatch | pbx_draining | not_answered
  def message
    @data.to_s
  end

  def http_status
    409
  end
end
