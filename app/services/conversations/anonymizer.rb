# Replaces personal data in conversation text with placeholders so the export can be shared
# or used for model training without leaking customer information.
class Conversations::Anonymizer
  PATTERNS = [
    [/\b\d{13}\b/, '[RUC]'],
    [/\b\d{10}\b/, '[CEDULA]'], # also catches local phone numbers 09xxxxxxxx
    [/\+?593[\s-]?\d[\d\s-]{7,10}/, '[TELEFONO]'],
    [/[\w.+-]+@[\w-]+\.[\w.-]+/, '[EMAIL]'],
    [/\b\d(?:[ -]?\d){12,18}\b/, '[TARJETA]'],
    [%r{https?://\S+}, '[URL]']
  ].freeze
  NAME_PLACEHOLDER = '[NOMBRE]'.freeze
  MIN_NAME_LENGTH = 4

  def initialize(names = [])
    @name_patterns = names.compact.flat_map { |name| patterns_for_name(name.strip) }
  end

  def call(text)
    result = text.to_s
    PATTERNS.each { |pattern, placeholder| result = result.gsub(pattern, placeholder) }
    @name_patterns.each { |pattern| result = result.gsub(pattern, NAME_PLACEHOLDER) }
    result.squish.gsub(/\[NOMBRE\]( \[NOMBRE\])+/, NAME_PLACEHOLDER) # "María José" -> one placeholder
  end

  private

  # Full name first, then each word long enough to identify someone ("Juan Pérez" and "Pérez").
  def patterns_for_name(name)
    return [] if name.length < MIN_NAME_LENGTH

    parts = name.split.select { |part| part.length >= MIN_NAME_LENGTH }
    [Regexp.new(Regexp.escape(name), Regexp::IGNORECASE)] +
      parts.map { |part| Regexp.new("\\b#{Regexp.escape(part)}\\b", Regexp::IGNORECASE) }
  end
end
