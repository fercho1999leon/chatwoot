require 'rails_helper'

RSpec.describe Telephony::InboundResolver do
  let(:account) { create(:account) }
  let(:call_id) { SecureRandom.uuid }
  let(:did) { '593000000000' }

  before { allow(OnlineStatusTracker).to receive(:get_available_users).and_return({}) }

  def resolve(caller: '+593987654321')
    described_class.new(account: account, call_id: call_id, caller_e164: caller, did: did).resolve
  end

  context 'when the account has a telephony inbox' do
    let!(:telephony_inbox) { create(:channel_telephony, account: account).inbox }

    it 'creates the contact and a conversation in the telephony inbox for an unknown number' do
      expect { resolve }.to change(Contact, :count).by(1).and change(Conversation, :count).by(1)

      contact = account.contacts.find_by(phone_number: '+593987654321')
      conversation = account.conversations.last
      expect(contact.name).to eq('+593987654321')
      expect(conversation.inbox).to eq(telephony_inbox)
      expect(conversation.contact).to eq(contact)
    end

    it 'reuses the most recent open conversation of a known contact, in any inbox' do
      contact = create(:contact, account: account, phone_number: '+593987654321', name: 'Ana')
      whatsapp_inbox = create(:inbox, account: account)
      contact_inbox = create(:contact_inbox, contact: contact, inbox: whatsapp_inbox)
      conversation = create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, contact_inbox: contact_inbox)

      result = nil
      expect { result = resolve }.not_to change(Conversation, :count)
      expect(result[:conversation_id]).to eq(conversation.id)
      expect(result[:conversation_display_id]).to eq(conversation.display_id)
      expect(result[:inbox_id]).to eq(whatsapp_inbox.id)
      expect(result[:contact_id]).to eq(contact.id)
      expect(result[:contact_name]).to eq('Ana')
    end

    it 'creates the inbound projection and returns the routing plan' do
      result = resolve

      projection = Telephony::CallProjection.find(result[:projection_id])
      expect(projection).to have_attributes(external_call_id: call_id, direction: 'inbound', did: did, state: 'requested',
                                            destination_e164: '+593987654321', user_id: nil, inbox_id: telephony_inbox.id)
      expect(projection.conversation_id).to eq(result[:conversation_id])
      expect(result[:plan]).to eq([{ type: 'hangup' }])
    end
  end

  it 'refuses unknown callers when there is no telephony inbox' do
    expect { resolve }.to raise_error(CustomExceptions::Telephony::Invalid, 'no_telephony_inbox')
  end
end
