class Telephony::CallProjectionPolicy < ApplicationPolicy
  # Solo el dueño de la llamada o un administrador de la cuenta.
  def show?
    @account_user.administrator? || record.user_id == @user.id
  end
end
