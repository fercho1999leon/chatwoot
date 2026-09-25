# DIDs de la troncal: misma regla que el telephony-controller (src/phone.ts + src/pbx/dids.ts) para que
# Chatwoot y el controlador decidan igual si dos DIDs son el mismo número (+593…, 593…, 00593… o 02…).
module Telephony::Did
  COUNTRY_CODES = { 'EC' => '593' }.freeze

  module_function

  # Dígitos E.164 si el DID se puede normalizar; si no, sus dígitos tal cual.
  def key(did, default_country = '')
    digits = did.to_s.gsub(/\D/, '')
    return digits.delete_prefix('00') if digits.match?(/\A00[1-9]\d{6,14}\z/)

    cc = COUNTRY_CODES[default_country.to_s.upcase]
    return "#{cc}#{digits[1..]}" if cc && digits.match?(/\A0\d{8,9}\z/)

    digits
  end
end
