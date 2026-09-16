# Borrado «mejor esfuerzo» del archivo de grabación que pueda seguir en la PBX. Se usa al purgar (retención
# o a mano) una grabación que nunca llegó a recogerse: si el controlador o la PBX no responden no se bloquea
# la purga local; el barrido del controlador (`recording_missing`) y la retención de la PBX cierran el resto.
class Telephony::RecordingRemote
  REMOTE_STATES = %w[stored failed].freeze

  def self.delete(projection)
    return false unless REMOTE_STATES.include?(projection.recording_state) && projection.recording_name.present?

    Telephony::ControllerClient.new.delete_recording(projection.external_call_id)
    true
  rescue Telephony::ControllerClient::Error => e
    Rails.logger.warn("telephony: no se pudo borrar la grabación remota de #{projection.external_call_id}: #{e.message}")
    false
  end
end
