# Turns one conversation into a fine-tuning sample (chat turns) or a raw JSON record.
# Expects messages, senders, contact, inbox and csat_survey_response to be preloaded.
class Conversations::DatasetBuilder
  DEFAULT_OPTIONS = {
    anonymize: true,
    include_private_notes: false,
    include_bot_messages: false,
    min_agent_messages: 2,
    min_user_messages: 1,
    min_csat: nil,
    system_prompt: nil
  }.freeze

  attr_reader :drop_reason

  def initialize(conversation, options = {})
    @conversation = conversation
    @options = DEFAULT_OPTIONS.merge(options.to_h.symbolize_keys)
  end

  # {"messages": [system, user, assistant, ...], "meta": {...}} or nil (see #drop_reason)
  def chat_sample
    return drop(:csat) unless csat_ok?

    turns = trim_turns(merge_turns(text_messages))
    return drop(:too_short) unless enough_turns?(turns)

    {
      messages: [{ role: 'system', content: system_prompt }] + turns,
      meta: {
        conversation_id: @conversation.display_id,
        inbox: @conversation.inbox.name,
        created_at: @conversation.created_at.iso8601,
        agents: agent_names.sort,
        csat: csat_rating,
        turns: turns.size
      }
    }
  end

  def raw_sample
    {
      id: @conversation.display_id,
      inbox: @conversation.inbox.name,
      status: @conversation.status,
      created_at: @conversation.created_at.iso8601,
      csat: csat_rating,
      contact: { id: @conversation.contact_id, name: clean(@conversation.contact&.name) },
      messages: exportable_messages.map { |message| raw_message(message) }
    }
  end

  private

  def raw_message(message)
    {
      id: message.id,
      type: message.message_type,
      content_type: message.content_type,
      sender: { type: message.sender_type, id: message.sender_id, name: clean(message.sender.try(:name)) },
      private: message.private,
      content: clean(message.content),
      created_at: message.created_at.iso8601,
      attachments: message.attachments.map { |attachment| { file_type: attachment.file_type, url: attachment.download_url } }
    }
  end

  # Messages exchanged between the contact and the agents, honouring the private/bot options.
  def exportable_messages
    @exportable_messages ||= @conversation.messages.sort_by { |message| [message.created_at, message.id] }.reject do |message|
      (message.private? && !@options[:include_private_notes]) ||
        (message.sender_type == 'AgentBot' && !@options[:include_bot_messages])
    end
  end

  def text_messages
    exportable_messages.select { |message| (message.incoming? || message.outgoing?) && message.text? && message.content.present? }
  end

  def merge_turns(messages)
    messages.each_with_object([]) do |message, turns|
      content = clean(message.content)
      next if content.blank?

      role = message.incoming? ? 'user' : 'assistant'
      if turns.last && turns.last[:role] == role
        turns.last[:content] += "\n#{content}"
      else
        turns << { role: role, content: content }
      end
    end
  end

  # A useful sample starts with the customer and ends with the agent.
  def trim_turns(turns)
    turns = turns.drop_while { |turn| turn[:role] != 'user' }
    turns.reverse.drop_while { |turn| turn[:role] != 'assistant' }.reverse
  end

  def enough_turns?(turns)
    turns.count { |turn| turn[:role] == 'assistant' } >= @options[:min_agent_messages].to_i &&
      turns.count { |turn| turn[:role] == 'user' } >= @options[:min_user_messages].to_i
  end

  def csat_ok?
    return true if @options[:min_csat].blank?

    csat_rating.present? && csat_rating >= @options[:min_csat].to_i
  end

  def csat_rating
    @conversation.csat_survey_response&.rating
  end

  def system_prompt
    @options[:system_prompt].presence || I18n.t('conversations.dataset_export.default_system_prompt')
  end

  def agent_names
    exportable_messages.filter_map { |message| message.sender.name if message.sender_type == 'User' }.uniq
  end

  def clean(text)
    return text if text.nil? || !@options[:anonymize]

    anonymizer.call(text)
  end

  def anonymizer
    @anonymizer ||= Conversations::Anonymizer.new([@conversation.contact&.name] + agent_names)
  end

  def drop(reason)
    @drop_reason = reason
    nil
  end
end
