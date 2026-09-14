# Lectura de TELEPHONY_*: la variable de entorno (Secret del despliegue) manda;
# si no está, el valor de Super Admin → App Config. Sin esto, el registro vacío
# que ConfigLoader crea desde installation_config.yml tapa al ENV.
module Telephony::Config
  def self.get(key)
    ENV.fetch(key, '').presence || GlobalConfigService.load(key, '').to_s
  end
end
