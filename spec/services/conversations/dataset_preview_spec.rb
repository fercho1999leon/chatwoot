require 'rails_helper'

RSpec.describe Conversations::DatasetPreview do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

  before do
    2.times do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, conversation: conversation, account: account, inbox: inbox, content: 'Hola')
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :outgoing, content: 'Te ayudo')
      conversation.resolved!
    end
    short = create(:conversation, account: account, inbox: inbox)
    create(:message, conversation: short, account: account, inbox: inbox, content: 'Solo yo')
    short.resolved!
  end

  it 'counts what the export would keep and returns one sample' do
    result = described_class.new(account, user, { status: 'resolved', options: { min_agent_messages: 1 } }.with_indifferent_access).perform

    expect(result).to include(matching_count: 3, analyzed_count: 3, kept_count: 2)
    expect(result[:dropped]).to eq(too_short: 1)
    expect(result[:sample][:messages].map { |message| message[:role] }).to eq(%w[system user assistant])
  end

  it 'reports an empty result when the minimum turns discards everything' do
    result = described_class.new(account, user, { status: 'resolved', options: { min_agent_messages: 5 } }.with_indifferent_access).perform

    expect(result).to include(kept_count: 0, dropped: { too_short: 3 }, sample: nil)
  end

  it 'analyses at most PREVIEW_SIZE conversations' do
    stub_const("#{described_class}::PREVIEW_SIZE", 1)

    result = described_class.new(account, user, { status: 'resolved', options: { min_agent_messages: 1 } }.with_indifferent_access).perform

    expect(result).to include(matching_count: 3, analyzed_count: 1)
  end
end
