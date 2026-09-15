class Telephony::CallProjectionPolicy < ApplicationPolicy
  # Solo el dueño de la llamada o un administrador de la cuenta.
  def show?
    @account_user.administrator? || record.involved_user_ids.include?(@user.id)
  end
end
