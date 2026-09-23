class Account::ConversationsDatasetExportJob < ApplicationJob
  queue_as :low

  FORMATS = %w[chat_jsonl raw_json].freeze
  DEFAULT_EVAL_RATIO = 0.1
  SPLIT_SEED = 42

  def perform(account_id, user_id, params)
    @account = Account.find(account_id)
    @account_user = @account.users.find(user_id)
    @params = params.with_indifferent_access
    @options = @params[:options].to_h
    @stats = Hash.new(0)
    @dataset_export = @account.dataset_exports.create!(user: @account_user, export_format: @params[:export_format], params: @params)

    with_user_locale do
      @params[:export_format] == 'raw_json' ? export_raw_json : export_chat_jsonl
    end
    @dataset_export.update!(status: :completed, conversations_count: @stats[:conversations_read])
    send_mail
  rescue StandardError => e
    @dataset_export&.update(status: :failed, error_message: e.message)
    raise
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

  def each_conversation(&)
    @stats[:conversations_read] = selection.each_conversation(&)
  end

  def selection
    @selection ||= Conversations::DatasetSelection.new(@account, @account_user, @params)
  end

  # Translated content (default system prompt) follows the dashboard language of the requesting user.
  def with_user_locale(&)
    locale = @account_user.ui_settings&.dig('locale').presence || @account.locale
    I18n.with_locale(I18n.locale_available?(locale) ? locale : I18n.default_locale, &)
  end

  def attach_export_file(data, filename, content_type)
    @dataset_export.file.attach(
      io: StringIO.new(data),
      filename: "#{@account.name}_#{@account.id}_#{filename}",
      content_type: content_type
    )
  end

  def send_mail
    mailer = AdministratorNotifications::AccountNotificationMailer.with(account: @account)
    mailer.conversations_dataset_export_complete(@dataset_export.file_url, @account_user.email)&.deliver_later
  end
end
