# frozen_string_literal: true

class CustomExceptions::Telephony::Unavailable < CustomExceptions::Base
  def message
    @data.to_s
  end

  def http_status
    503
  end
end
