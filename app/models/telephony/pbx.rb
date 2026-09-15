# == Schema Information
#
# Table name: telephony_pbxes
#
#  id                       :bigint           not null, primary key
#  agent_timeout            :integer          default(30), not null
#  ari_app                  :string           default("chatwoot"), not null
#  ari_url                  :string           default(""), not null
#  ari_user                 :string           default(""), not null
#  bot_token_digest         :string
#  bot_webhook_url          :string           default(""), not null
#  has_ari_password         :boolean          default(FALSE), not null
#  has_provision_token      :boolean          default(FALSE), not null
#  has_turn_secret          :boolean          default(FALSE), not null
#  max_call_seconds         :integer          default(3600), not null
#  provision_url            :string           default(""), not null
#  pstn_timeout             :integer          default(45), not null
#  record_calls             :string           default("never"), not null
#  recording_retention_days :integer          default(0), not null
#  sip_domain               :string           default(""), not null
#  sip_ws_url               :string           default(""), not null
#  stun_url                 :string           default(""), not null
#  sync_error               :string
#  synced_at                :datetime
#  test_dial                :string           default(""), not null
#  transfer_timeout         :integer          default(30), not null
#  turn_ttl_seconds         :integer          default(3600), not null
#  turn_urls                :string           default(""), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_telephony_pbxes_on_account_id        (account_id) UNIQUE
#  index_telephony_pbxes_on_bot_token_digest  (bot_token_digest) UNIQUE
#

# Conexión de la cuenta a su PBX (Asterisk/FreePBX). Los secretos (ARI, TURN, provisioner)
# viajan al telephony-controller y no se persisten aquí: solo si están definidos.
class Telephony::Pbx < ApplicationRecord
  self.table_name = 'telephony_pbxes'

  belongs_to :account

  EDITABLE_ATTRS = %i[ari_url ari_user ari_app sip_ws_url sip_domain stun_url turn_urls turn_ttl_seconds provision_url
                      test_dial agent_timeout transfer_timeout pstn_timeout max_call_seconds record_calls
                      recording_retention_days bot_webhook_url].freeze
  # Lo que viaja al controlador (la retención y el webhook del bot los aplica Chatwoot).
  CONTROLLER_ATTRS = (EDITABLE_ATTRS - %i[recording_retention_days bot_webhook_url]).freeze
  RECORD_MODES = %w[never inbound outbound all].freeze
  SECRET_ATTRS = %i[ari_password turn_secret provision_token].freeze
  MASK = '********'.freeze

  attr_accessor(*SECRET_ATTRS)

  validates :ari_url, format: { with: %r{\Ahttps?://\S+\z} }
  validates :ari_user, :sip_domain, presence: true
  validates :ari_app, format: { with: /\A[A-Za-z0-9_-]{1,40}\z/ }
  validates :sip_ws_url, format: { with: %r{\Awss?://\S+\z} }
  validates :provision_url, :bot_webhook_url, format: { with: %r{\A(https?://\S+)?\z} }
  validates :turn_ttl_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 300, less_than_or_equal_to: 86_400 }
  validates :agent_timeout, :transfer_timeout, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 120 }
  validates :pstn_timeout, numericality: { only_integer: true, greater_than_or_equal_to: 10, less_than_or_equal_to: 180 }
  validates :max_call_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 60, less_than_or_equal_to: 14_400 }
  validates :record_calls, inclusion: { in: RECORD_MODES }
  validates :recording_retention_days, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 3650 }

  before_validation :track_secrets

  # Cuenta dueña del token de la API del bot (Authorization: Bearer <token>); nil si no coincide.
  def self.authenticate_bot_token(token)
    return nil if token.blank?

    find_by(bot_token_digest: Digest::SHA256.hexdigest(token))
  end

  def configured?
    ari_url.present? && sip_ws_url.present? && has_ari_password
  end

  # Cuerpo para PUT /internal/pbx. Secreto nil o '********' = el controlador conserva el suyo;
  # '' = borrarlo; otro valor = nuevo.
  def controller_payload
    config = CONTROLLER_ATTRS.index_with { |a| public_send(a) }
    SECRET_ATTRS.each { |a| config[a] = public_send(a).nil? ? MASK : public_send(a) }
    { account_id: account_id, config: config }
  end

  # Token de la API del bot: se devuelve en claro una sola vez; aquí queda solo su SHA256.
  def generate_bot_token!
    token = SecureRandom.hex(32)
    update!(bot_token_digest: Digest::SHA256.hexdigest(token))
    token
  end

  def revoke_bot_token!
    update!(bot_token_digest: nil)
  end

  def has_bot_token? # rubocop:disable Naming/PredicateName
    bot_token_digest.present?
  end

  def bot_token_matches?(token)
    return false if token.blank? || bot_token_digest.blank?

    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(token), bot_token_digest)
  end

  private

  def track_secrets
    SECRET_ATTRS.each do |attr|
      value = public_send(attr)
      public_send(:"#{attr}=", nil) if value == MASK
      public_send(:"has_#{attr}=", value.present?) unless value.nil? || value == MASK
    end
  end
end
