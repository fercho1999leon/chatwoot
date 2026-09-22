require 'rails_helper'

RSpec.describe Account::ConversationsDatasetExportJob do
  subject(:job) { described_class.perform_later(account.id, user.id, { export_format: 'chat_jsonl' }) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator, email: 'admin@test.com') }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }
  let(:mailer) { double }

  before do
    allow(AdministratorNotifications::AccountNotificationMailer).to receive(:with).with(account: account).and_return(mailer)
    allow(mailer).to receive(:conversations_dataset_export_complete)

    3.times do |i|
      conversation = create(:conversation, account: account, inbox: inbox, created_at: i.days.ago)
      create(:message, conversation: conversation, account: account, inbox: inbox, content: "Problema #{i}")
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'Reviso')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'Listo')
      conversation.resolved!
    end
    open_conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    create(:message, conversation: open_conversation, account: account, inbox: inbox, content: 'Abierta')
    create(:message, conversation: open_conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'Ok')
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class).on_queue('low')
  end

  it 'exports a chat_jsonl zip of resolved conversations and sends the mail' do
    described_class.perform_now(account.id, user.id, { export_format: 'chat_jsonl', options: { min_agent_messages: 1 } })

    export = account.conversations_dataset_export
    expect(export.filename.to_s).to end_with('_dataset.zip')
    entries = Zip::File.open_buffer(export.download).each_with_object({}) { |entry, memo| memo[entry.name] = entry.get_input_stream.read }
    expect(entries.keys).to contain_exactly('train.jsonl', 'eval.jsonl', 'stats.json')

    train = entries['train.jsonl'].lines.map { |line| JSON.parse(line) }
    expect(train.size).to eq(3)
    expect(train.map { |sample| sample['messages'].map { |m| m['role'] } }).to all(eq(%w[system user assistant]))
    expect(train.map { |sample| sample['messages'].last['content'] }).to all(eq("Reviso\nListo"))

    stats = JSON.parse(entries['stats.json'])
    expect(stats).to include('conversations_read' => 3, 'conversations_kept' => 3, 'train' => 3, 'eval' => 0)

    file_url = Rails.application.routes.url_helpers.rails_blob_url(export)
    expect(mailer).to have_received(:conversations_dataset_export_complete).with(file_url, user.email)
  end

  it 'uses the default system prompt in the language of the requesting user' do
    user.update!(ui_settings: { locale: 'es' })

    described_class.perform_now(account.id, user.id, { export_format: 'chat_jsonl', options: { min_agent_messages: 1 } })

    entries = Zip::File.open_buffer(account.conversations_dataset_export.download).to_a.index_by(&:name)
    sample = JSON.parse(entries['train.jsonl'].get_input_stream.read.lines.first)
    expect(sample['messages'].first['content']).to eq(I18n.t('conversations.dataset_export.default_system_prompt', locale: :es))
  end

  it 'counts dropped conversations in stats' do
    described_class.perform_now(account.id, user.id, { export_format: 'chat_jsonl', options: { min_agent_messages: 5 } })

    entries = Zip::File.open_buffer(account.conversations_dataset_export.download).to_a.index_by(&:name)
    stats = JSON.parse(entries['stats.json'].get_input_stream.read)

    expect(stats).to include('conversations_read' => 3, 'conversations_kept' => 0, 'dropped_too_short' => 3)
    expect(entries['train.jsonl'].get_input_stream.read).to eq('')
  end

  it 'applies status, limit and inbox filters to raw_json exports' do
    other_inbox = create(:inbox, account: account)
    create(:conversation, account: account, inbox: other_inbox, status: :open)

    described_class.perform_now(account.id, user.id, { export_format: 'raw_json', status: 'open', inbox_ids: [inbox.id], limit: 5, options: {} })

    export = account.conversations_dataset_export
    expect(export.filename.to_s).to end_with('_conversations.json')
    records = JSON.parse(export.download)
    expect(records.size).to eq(1)
    expect(records.first['status']).to eq('open')
    expect(records.first['messages'].map { |m| m['content'] }).to eq(%w[Abierta Ok])
  end

  it 'selects conversations with the advanced filter payload' do
    payload = [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }]

    described_class.perform_now(account.id, user.id, { export_format: 'raw_json', payload: payload, limit: 1 })

    records = JSON.parse(account.conversations_dataset_export.download)
    expect(records.map { |record| record['status'] }).to eq(['open'])
  end
end
