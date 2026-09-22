class Account::ConversationsDatasetExportJob < ApplicationJob
  queue_as :low

  FORMATS = %w[chat_jsonl raw_json].freeze
  MAX_CONVERSATIONS = 50_000
  BATCH_SIZE = 200
  DEFAULT_EVAL_RATIO = 0.1
  SPLIT_SEED = 42

  def perform(account_id, user_id, params)
    @account = Account.find(account_id)
    @account_user = @account.users.find(user_id)
    @params = params.with_indifferent_access
    @options = @params[:options].to_h
    @stats = Hash.new(0)

    with_user_locale do
      @params[:export_format] == 'raw_json' ? export_raw_json : export_chat_jsonl
    end
    send_mail
  end

  private

  def export_chat_jsonl
    samples = []
    each_conversation do |conversation|
      builder = Conversations::DatasetBuilder.new(conversation, @options)
      sample = builder.chat_sample
      sample ? samples << count_sample(sample) : @stats["dropped_#{builder.drop_reason}"] += 1
    end

    samples.shuffle!(random: Random.new(SPLIT_SEED))
    eval_count = (samples.size * eval_ratio).to_i
    @stats.merge!(conversations_kept: samples.size, eval: eval_count, train: samples.size - eval_count)
    attach_export_file(zip_dataset(samples.drop(eval_count), samples.first(eval_count)), 'dataset.zip', 'application/zip')
  end

  def count_sample(sample)
    @stats["inbox:#{sample[:meta][:inbox]}"] += 1
    sample[:meta][:agents].each { |agent| @stats["agent:#{agent}"] += 1 }
    sample
  end

  def zip_dataset(train, eval_samples)
    Zip::OutputStream.write_buffer do |archive|
      archive.put_next_entry('train.jsonl')
      archive.write(jsonl(train))
      archive.put_next_entry('eval.jsonl')
      archive.write(jsonl(eval_samples))
      archive.put_next_entry('stats.json')
      archive.write(JSON.pretty_generate(@stats))
    end.string
  end

  def export_raw_json
    records = []
    each_conversation { |conversation| records << Conversations::DatasetBuilder.new(conversation, @options).raw_sample }
    attach_export_file(JSON.generate(records), 'conversations.json', 'application/json')
  end

  def jsonl(samples)
    samples.map { |sample| "#{JSON.generate(sample)}\n" }.join
  end

  def eval_ratio
    (@options[:eval_ratio].presence || DEFAULT_EVAL_RATIO).to_f
  end

  # Loads the selected conversations newest first, in batches, with everything the builder needs.
  def each_conversation
    ids = conversations.reorder(created_at: :desc).limit(limit).pluck(:id)
    @stats[:conversations_read] = ids.size

    ids.each_slice(BATCH_SIZE) do |batch_ids|
      batch = Conversation.where(id: batch_ids)
                          .preload(:inbox, :contact, :csat_survey_response, messages: [:sender, :attachments])
                          .index_by(&:id)
      batch_ids.each { |id| yield batch[id] }
    end
  end

  def conversations
    return ::Conversations::FilterService.new(@params, @account_user, @account).filtered_conversations if @params[:payload].present?

    scope = @account.conversations.where(status: @params[:status].presence || :resolved)
    scope = scope.where(inbox_id: @params[:inbox_ids]) if @params[:inbox_ids].present?
    scope = scope.where(created_at: @params[:since]..) if @params[:since].present?
    scope = scope.where(created_at: ..@params[:until]) if @params[:until].present?
    scope
  end

  def limit
    [@params[:limit].presence&.to_i || MAX_CONVERSATIONS, MAX_CONVERSATIONS].min
  end

  # Translated content (default system prompt) follows the dashboard language of the requesting user.
  def with_user_locale(&)
    locale = @account_user.ui_settings&.dig('locale').presence || @account.locale
    I18n.with_locale(I18n.locale_available?(locale) ? locale : I18n.default_locale, &)
  end

  def attach_export_file(data, filename, content_type)
    @account.conversations_dataset_export.attach(
      io: StringIO.new(data),
      filename: "#{@account.name}_#{@account.id}_#{filename}",
      content_type: content_type
    )
  end

  def send_mail
    file_url = Rails.application.routes.url_helpers.rails_blob_url(@account.conversations_dataset_export)
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.conversations_dataset_export_complete(file_url, @account_user.email)&.deliver_later
  end
end
