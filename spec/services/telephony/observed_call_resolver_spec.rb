require 'rails_helper'

RSpec.describe Telephony::ObservedCallResolver do
  let(:account) { create(:account) }
  let(:call_id) { SecureRandom.uuid }
  let!(:telephony_inbox) { create(:channel_telephony, account: account).inbox }

  def resolve(did:, caller: '+593987654321', id: call_id)
    described_class.new(account: account, call_id: id, caller_e164: caller, did: did).resolve
  end

  it 'files a carrier DID call in the telephony inbox with a pbx-routed projection and no plan' do
    result = nil
    expect { result = resolve(did: '59322000000') }.to change(Contact, :count).by(1).and change(Conversation, :count).by(1)

    expect(result).not_to have_key(:plan)
    expect(Conversation.find(result[:conversation_id]).inbox).to eq(telephony_inbox)
    projection = Telephony::CallProjection.find_by(external_call_id: call_id)
    expect(projection).to have_attributes(source: 'pbx', direction: 'inbound', did: '59322000000', state: 'requested', user_id: nil)
  end

  it 'files a call to the WhatsApp number in its WhatsApp inbox, reusing the open conversation there' do
    whatsapp = create(:channel_whatsapp, account: account, phone_number: '+593988948797', validate_provider_config: false, sync_templates: false)
    contact = create(:contact, account: account, phone_number: '+593987654321', name: 'Ana')
    create(:conversation, account: account, inbox: telephony_inbox, contact: contact) # abierta en otro inbox: no se usa

    first = resolve(did: '593988948797')
    expect(Conversation.find(first[:conversation_id]).inbox).to eq(whatsapp.inbox)
    expect(first).to include(contact_id: contact.id, contact_name: 'Ana')
    expect(contact.contact_inboxes.find_by(inbox: whatsapp.inbox).source_id).to eq('593987654321')

    second = resolve(did: '+593988948797', id: SecureRandom.uuid)
    expect(second[:conversation_id]).to eq(first[:conversation_id])
  end

  it 'fails loudly without a telephony inbox for a carrier DID' do
    telephony_inbox.channel.destroy!
    expect { resolve(did: '59322000000') }.to raise_error(CustomExceptions::Telephony::Invalid)
  end
end
