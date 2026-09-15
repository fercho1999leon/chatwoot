# Ver una llamada no equivale a controlarla: el dueño anterior y los agentes a los que solo les
# sonó reciben sus eventos (show?), pero no pueden colgarla, retenerla ni transferirla.
class Telephony::CallProjectionPolicy < ApplicationPolicy
  # Administrador o cualquier usuario involucrado (dueño, destino, transferencia, sonando, participante).
  def show?
    admin? || record.involved_user_ids.include?(user_id)
  end

  # Colgar, retener, DTMF, transferir: dueño, participante (conferencia) o par interno con la
  # llamada contestada. Nunca el dueño anterior ni quien solo estaba sonando.
  def control?
    admin? || owner? || participant? || answered_peer?
  end

  # Volver a invitar (ring_me): a quien le suena, destino de transferencia o de llamada interna,
  # y dueño/participante (reinvitación tras recarga).
  def answer?
    admin? || ringing? || record.transfer_to_user_id == user_id || record.to_user_id == user_id || owner? || participant?
  end

  def leave?
    owner? || participant?
  end

  def destroy_recording?
    admin? || owner?
  end

  private

  def user_id
    @user.id
  end

  def admin?
    @account_user.administrator?
  end

  def owner?
    record.user_id == user_id
  end

  def participant?
    Array(record.participants).map(&:to_i).include?(user_id)
  end

  def ringing?
    Array(record.ringing_user_ids).map(&:to_i).include?(user_id)
  end

  def answered_peer?
    record.to_user_id == user_id && record.state == 'answered'
  end
end
