# frozen_string_literal: true

class CustomExceptions::Telephony::Invalid < CustomExceptions::Base
  # @data es el código: no_phone | inbox_not_enabled | no_endpoint | feature_disabled | policy_denied
  def message
    @data.to_s
  end

  def http_status
    422
  end
end
