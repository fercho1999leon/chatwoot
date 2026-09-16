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
  CONDITION_KEYS = %w[contact_known open_conversation assignee_online business_hours dids caller_prefix hint].freeze
  DESTINATION_KEYS = %w[type user_id team_id extension number ivr_id timeout expand max_seconds].freeze
  # max_seconds (solo extension): plazo de decisión de un bot de voz; si contesta y no deriva a tiempo se sigue con la cadena.
  MAX_SECONDS_RANGE = (5..600)
  # Campo obligatorio de cada tipo de destino (también lo usa la API del bot).
  REQUIRED_FIELD = { 'agent' => 'user_id', 'team' => 'team_id', 'extension' => 'extension', 'ringgroup' => 'number',
                     'ivr' => 'ivr_id', 'voicemail' => 'extension' }.freeze
  BOOLEANS = [true, false, 'true', 'false', nil].freeze

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
    %w[contact_known open_conversation assignee_online].each do |key|
      errors.add(:conditions, key) unless TRISTATE.include?(c.fetch(key, 'any'))
    end
    errors.add(:conditions, 'business_hours') unless HOURS.include?(c.fetch('business_hours', 'any'))
    errors.add(:conditions, 'hint') unless valid_hint?(c['hint'])
  end

  def valid_hint?(value)
    value.nil? || (value.is_a?(String) && value.length <= 80)
  end

  def destination_is_valid
    d = destination.to_h.stringify_keys
    errors.add(:destination, 'unknown key') if (d.keys - DESTINATION_KEYS).any?
    return errors.add(:destination, 'type') unless DESTINATIONS.include?(d['type'])

    required = REQUIRED_FIELD[d['type']]
    errors.add(:destination, "#{required} required") if required && d[required].blank?
    errors.add(:destination, 'expand') unless BOOLEANS.include?(d['expand'])
    errors.add(:destination, 'max_seconds') unless valid_max_seconds?(d)
  end

  def valid_max_seconds?(destination)
    value = destination['max_seconds']
    return true if value.blank?
    return false unless destination['type'] == 'extension'

    value.to_s.match?(/\A\d+\z/) && MAX_SECONDS_RANGE.cover?(value.to_i)
  end
end
