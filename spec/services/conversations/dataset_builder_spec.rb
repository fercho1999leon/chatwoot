require 'rails_helper'

RSpec.describe Conversations::DatasetBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, name: 'Soporte', channel: create(:channel_api, account: account)) }
  let(:contact) { create(:contact, account: account, name: 'Carlos Mendoza') }
  let(:agent) { create(:user, account: account, name: 'Lucía Torres') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:options) { {} }

  def message(content, type: :incoming, **attrs)
    sender = type == :incoming ? contact : agent
    create(:message, conversation: conversation, account: account, inbox: inbox, message_type: type, sender: sender, content: content, **attrs)
  end

  describe '#chat_sample' do
    before do
      message('Hola', type: :outgoing) # trimmed: sample must start with the customer
      message('Buenas, soy Carlos Mendoza, cédula 1712345678')
      message('no tengo internet')
      message('Hola Carlos, reviso', type: :outgoing)
      message('Nota interna', type: :outgoing, private: true)
      message('Ya está', type: :outgoing)
      message('sigue igual')
      message('Reinicie el router', type: :outgoing)
      message('Gracias') # trimmed: sample must end with the agent
      message('activity', type: :activity, sender: nil)
    end

    it 'builds merged, trimmed and anonymized turns with a system prompt' do
      sample = described_class.new(conversation.reload, options).chat_sample

      expect(sample[:messages].map { |turn| turn[:role] }).to eq(%w[system user assistant user assistant])
      expect(sample[:messages][0][:content]).to eq(I18n.t('conversations.dataset_export.default_system_prompt'))
      expect(sample[:messages][1][:content]).to eq("Buenas, soy [NOMBRE], cédula [CEDULA]\nno tengo internet")
      expect(sample[:messages][2][:content]).to eq("Hola [NOMBRE], reviso\nYa está")
      expect(sample[:meta]).to include(conversation_id: conversation.display_id, inbox: 'Soporte', agents: ['Lucía Torres'], csat: nil, turns: 4)
    end

    it 'keeps private notes and raw text when asked' do
      sample = described_class.new(conversation.reload, anonymize: false, include_private_notes: true, system_prompt: 'X').chat_sample

      expect(sample[:messages][0][:content]).to eq('X')
      expect(sample[:messages][1][:content]).to include('Carlos Mendoza, cédula 1712345678')
      expect(sample[:messages][2][:content]).to eq("Hola Carlos, reviso\nNota interna\nYa está")
    end

    it 'drops conversations below the minimum turns' do
      builder = described_class.new(conversation.reload, min_agent_messages: 3)

      expect(builder.chat_sample).to be_nil
      expect(builder.drop_reason).to eq(:too_short)
    end

    it 'drops conversations below the minimum csat' do
      builder = described_class.new(conversation.reload, min_agent_messages: 1, min_csat: 4)

      expect(builder.chat_sample).to be_nil
      expect(builder.drop_reason).to eq(:csat)
    end

    it 'keeps conversations rated at or above the minimum csat' do
      create(:csat_survey_response, account: account, conversation: conversation, contact: contact, rating: 4)
      sample = described_class.new(conversation.reload, min_agent_messages: 1, min_csat: 4).chat_sample

      expect(sample[:meta][:csat]).to eq(4)
    end
  end

  describe '#raw_sample' do
    before do
      message('Mi correo es carlos@mail.com')
      message('Listo', type: :outgoing, private: true)
    end

    it 'exports the conversation with its messages in order' do
      sample = described_class.new(conversation.reload, anonymize: false, include_private_notes: true).raw_sample

      expect(sample).to include(id: conversation.display_id, inbox: 'Soporte', status: 'open')
      expect(sample[:contact]).to eq(id: contact.id, name: 'Carlos Mendoza')
      expect(sample[:messages].map { |m| m[:content] }).to eq(['Mi correo es carlos@mail.com', 'Listo'])
      expect(sample[:messages].first).to include(type: 'incoming', private: false, attachments: [])
      expect(sample[:messages].first[:sender]).to eq(type: 'Contact', id: contact.id, name: 'Carlos Mendoza')
    end

    it 'anonymizes names and personal data and skips private notes by default' do
      sample = described_class.new(conversation.reload).raw_sample

      expect(sample[:contact][:name]).to eq('[NOMBRE]')
      expect(sample[:messages].map { |m| m[:content] }).to eq(['Mi correo es [EMAIL]'])
    end
  end
end
