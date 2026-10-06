require 'rails_helper'

RSpec.describe 'Telephony contact calls API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:client) { instance_double(Telephony::ControllerClient) }
  let(:path) { "/api/v1/accounts/#{account.id}/telephony/contact_calls" }
  let(:headers) { agent.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:telephony_inbox) { Channel::Telephony.find_by(account: account).inbox }

  before do
    allow(Telephony::ControllerClient).to receive_messages(configured?: true, new: client)
    allow(client).to receive(:create_call) { |args| { 'call_id' => args[:call_id], 'state' => 'requested', 'state_version' => 0 } }
    account.enable_features!('telephony_calls')
    create(:telephony_pbx, account: account)
    create(:channel_telephony, account: account, default_country: 'EC')
    create(:telephony_endpoint, account: account, user: agent)
  end

  context 'when dialing a number' do
    it 'creates the contact and its conversation in the Telephony inbox and dials the E.164 number' do
      expect do
        post path, params: { phone_number: '098 765 4321' }, headers: headers, as: :json
      end.to change(account.contacts, :count).by(1)

      expect(response).to have_http_status(:created)
      contact = account.contacts.find_by(phone_number: '+593987654321')
      expect(contact.name).to eq('+593987654321')
      expect(contact.conversations.last.inbox).to eq(telephony_inbox)
      expect(client).to have_received(:create_call).with(hash_including(destination_e164: '+593987654321', contact_id: contact.id))
    end

    it 'reuses the existing contact with that number' do
      contact = create(:contact, account: account, phone_number: '+593987654321')

      expect do
        post path, params: { phone_number: '+593987654321' }, headers: headers, as: :json
      end.not_to change(account.contacts, :count)

      expect(response).to have_http_status(:created)
      expect(client).to have_received(:create_call).with(hash_including(contact_id: contact.id))
    end

    it 'rejects numbers that cannot be normalized' do
      post path, params: { phone_number: '123' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('invalid_phone')
      expect(client).not_to have_received(:create_call)
    end
  end

  it 'still calls a contact by id' do
    contact = create(:contact, account: account, phone_number: '+593987654321')

    post path, params: { contact_id: contact.id }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(client).to have_received(:create_call).with(hash_including(contact_id: contact.id))
  end

  it 'refuses agents without an extension' do
    Telephony::Endpoint.where(user: agent).delete_all

    post path, params: { phone_number: '0987654321' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('no_endpoint')
  end
end
