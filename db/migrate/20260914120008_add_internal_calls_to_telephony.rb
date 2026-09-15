class AddInternalCallsToTelephony < ActiveRecord::Migration[7.1]
  def change
    # Llamadas internas (agente ↔ agente, sin conversación) y participantes de conferencia.
    change_column_null :telephony_call_projections, :conversation_id, true
    add_column :telephony_call_projections, :to_user_id, :integer
    add_column :telephony_call_projections, :participants, :jsonb, null: false, default: []
  end
end
