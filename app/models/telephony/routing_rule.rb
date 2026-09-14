# == Schema Information
#
# Table name: telephony_routing_rules
#
#  id          :bigint           not null, primary key
#  conditions  :jsonb            not null
#  destination :jsonb            not null
#  enabled     :boolean          default(TRUE), not null
#  name        :string           default(""), not null
#  position    :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_telephony_routing_rules_on_account_id  (account_id)
#

# Regla de enrutamiento de entrantes: condiciones sobre la llamada/contacto/conversación → destino.
# Se evalúan en orden; cada regla que aplica aporta un paso al plan (agentes, extensión, ring group)
# hasta un destino terminal (IVR, buzón, colgar).
class Telephony::RoutingRule < ApplicationRecord
  self.table_name = 'telephony_routing_rules'

  belongs_to :account

  TRISTATE = %w[any yes no].freeze
  HOURS = %w[any in out].freeze
  DESTINATIONS = %w[assignee agent team extension ringgroup ivr voicemail hangup].freeze
  TERMINAL = %w[ivr voicemail hangup].freeze
  CONDITION_KEYS = %w[contact_known open_conversation assignee_online business_hours dids caller_prefix].freeze
  DESTINATION_KEYS = %w[type user_id team_id extension number ivr_id timeout].freeze

  validates :name, length: { maximum: 80 }
  validate :conditions_are_valid
  validate :destination_is_valid

  scope :ordered, -> { order(:position, :id) }

  def terminal?
    TERMINAL.include?(destination['type'])
  end

  def timeout
    (destination['timeout'].presence || 20).to_i.clamp(5, 120)
  end

  private

  def conditions_are_valid
    c = conditions.to_h.stringify_keys
    errors.add(:conditions, 'unknown key') if (c.keys - CONDITION_KEYS).any?
    errors.add(:conditions, 'contact_known') unless TRISTATE.include?(c.fetch('contact_known', 'any'))
    errors.add(:conditions, 'open_conversation') unless TRISTATE.include?(c.fetch('open_conversation', 'any'))
    errors.add(:conditions, 'assignee_online') unless TRISTATE.include?(c.fetch('assignee_online', 'any'))
    errors.add(:conditions, 'business_hours') unless HOURS.include?(c.fetch('business_hours', 'any'))
  end

  def destination_is_valid
    d = destination.to_h.stringify_keys
    errors.add(:destination, 'unknown key') if (d.keys - DESTINATION_KEYS).any?
    return errors.add(:destination, 'type') unless DESTINATIONS.include?(d['type'])

    required = { 'agent' => 'user_id', 'team' => 'team_id', 'extension' => 'extension', 'ringgroup' => 'number',
                 'ivr' => 'ivr_id', 'voicemail' => 'extension' }[d['type']]
    errors.add(:destination, "#{required} required") if required && d[required].blank?
  end
end
