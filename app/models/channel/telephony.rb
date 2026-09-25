# == Schema Information
#
# Table name: channel_telephony
#
#  id                :bigint           not null, primary key
#  allowed_inbox_ids :jsonb            not null
#  auth_mode         :string           default("register"), not null
#  carrier_ips       :jsonb            not null
#  codecs            :jsonb            not null
#  default_country   :string           default(""), not null
#  dids              :string           default(""), not null
#  dtmf              :string           default("rfc4733"), not null
#  host              :string           default(""), not null
#  max_call_seconds  :integer          default(3600), not null
#  password          :string           default(""), not null
#  port              :integer          default(5060), not null
#  provision_error   :string
#  provisioned_at    :datetime
#  register          :boolean          default(TRUE), not null
#  transport         :string           default("udp"), not null
#  trunk_mode        :string           default("custom"), not null
#  trunk_name        :string           default(""), not null
#  username          :string           default(""), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  caller_id         :string           default(""), not null
#
# Indexes
#
#  index_channel_telephony_on_account_id  (account_id)
#

# Canal "Telephony (SIP)": la troncal de la cuenta, editable desde Settings → Inboxes.
# Los colaboradores del inbox son los agentes con extensión (Telephony::Endpoint).
class Channel::Telephony < ApplicationRecord
  include Channelable

  self.table_name = 'channel_telephony'
  EDITABLE_ATTRS = [:trunk_mode, :trunk_name, :host, :port, :transport, :auth_mode, :username, :password, :caller_id, :dtmf, :register,
                    :default_country, :max_call_seconds, :dids, { carrier_ips: [], codecs: [], allowed_inbox_ids: [] }].freeze

  # custom: Chatwoot escribe la troncal; gui: troncal fija de FreePBX; routes: Outbound Routes de FreePBX (varios carriers)
  TRUNK_MODES = %w[custom gui routes].freeze
  TRANSPORTS = %w[udp tcp tls].freeze
  AUTH_MODES = %w[register ip].freeze
  CODECS = %w[ulaw alaw g722 opus g729 gsm].freeze
  DTMF_MODES = %w[rfc4733 inband info auto].freeze
  MASKED_PASSWORD = '********'.freeze

  # Una troncal por cuenta: el controlador guarda una sola (trunk-<account_id>). Varios carriers → modo routes.
  validates :account_id, uniqueness: true
  validates :trunk_mode, inclusion: { in: TRUNK_MODES }
  # Usuario y contraseña terminan en pjsip.conf: un salto de línea permitiría inyectar secciones.
  validates :username, :password, format: { without: /[[:cntrl:]]/ }
  validates :trunk_name, format: { with: /\A[A-Za-z0-9_-]*\z/ }
  validates :transport, inclusion: { in: TRANSPORTS }
  validates :auth_mode, inclusion: { in: AUTH_MODES }
  validates :dtmf, inclusion: { in: DTMF_MODES }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }
  validates :max_call_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 60,
                                               less_than_or_equal_to: 14_400 }
  validates :host, format: { with: /\A[A-Za-z0-9.-]*\z/ }
  validates :dids, format: { with: /\A[\d+,\s]*\z/ }
  validate :codecs_are_known
  validate :carrier_ips_are_ips
  validate :dids_not_claimed_elsewhere

  before_validation :normalize
  after_commit :sync_to_controller, on: [:create, :update]
  after_destroy_commit :remove_from_controller

  def name
    'Telephony'
  end

  def configured?
    case trunk_mode
    when 'gui' then trunk_name.present?
    when 'routes' then true
    else host.present?
    end
  end

  # Nombre PJSIP con el que marca el controlador.
  def dial_trunk_name
    case trunk_mode
    when 'gui' then trunk_name
    when 'routes' then 'from-internal'
    else "trunk-#{account_id}"
    end
  end

  # DIDs como los entrega el operador: solo dígitos, sin duplicados ("+593 22 000 000" → "59322000000").
  def did_list
    dids.to_s.split(',').map { |did| did.gsub(/\D/, '') }.compact_blank.uniq
  end

  # Un inbox puede llamar si la lista está vacía (todos) o lo incluye.
  def allows_inbox?(inbox_id)
    allowed_inbox_ids.blank? || allowed_inbox_ids.map(&:to_i).include?(inbox_id.to_i)
  end

  def controller_payload
    {
      account_id: account_id, mode: trunk_mode, trunk_name: trunk_name, host: host, port: port, transport: transport,
      auth: auth_mode, username: username, password: password, carrier_ips: carrier_ips, caller_id: caller_id,
      codecs: codecs, dtmf: dtmf, register: register, default_country: default_country, max_call_seconds: max_call_seconds,
      dids: dids
    }
  end

  private

  def normalize
    normalize_lists
    self.dids = did_list.join(', ')
    self.caller_id = caller_id.to_s.gsub(/[^0-9+]/, '')
    # La UI manda '********' para conservar la contraseña guardada.
    self.password = password_was.to_s if password == MASKED_PASSWORD
  end

  def normalize_lists
    self.carrier_ips = Array(carrier_ips).map { |ip| ip.to_s.strip }.compact_blank.uniq
    self.codecs = Array(codecs).map(&:to_s).compact_blank.uniq.presence || %w[ulaw alaw]
    self.allowed_inbox_ids = Array(allowed_inbox_ids).map(&:to_i).uniq
  end

  def codecs_are_known
    errors.add(:codecs, 'unknown codec') unless (codecs - CODECS).empty?
  end

  def carrier_ips_are_ips
    bad = carrier_ips.grep_v(%r{\A\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?\z})
    errors.add(:carrier_ips, "invalid: #{bad.join(', ')}") if bad.any?
  end

  # Un DID tiene un solo dueño: si otra cuenta lo declara, la entrante iría a la cuenta más antigua.
  # Se compara por la forma E.164 (así 022000000 con EC choca con 59322000000). El controlador
  # repite la comprobación contra los números de WhatsApp de otras cuentas.
  def dids_not_claimed_elsewhere
    mine = did_list.index_by { |did| Telephony::Did.key(did, default_country) }
    return if mine.empty?

    self.class.where.not(account_id: account_id).find_each do |other|
      taken = other.did_list.filter_map { |did| mine[Telephony::Did.key(did, other.default_country)] }
      errors.add(:dids, "already used by another account: #{taken.join(', ')}") if taken.any?
    end
  end

  def sync_to_controller
    return unless configured?

    Telephony::TrunkSyncJob.perform_later(id)
  end

  def remove_from_controller
    Telephony::TrunkRemoveJob.perform_later(account_id)
  end
end
