require 'rails_helper'

RSpec.describe 'Dataset Exports API', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/dataset_exports' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/dataset_exports"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/dataset_exports", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'lists the exports of the account, newest first' do
        older = create(:dataset_export, account: account, user: admin, created_at: 2.days.ago)
        newer = create(:dataset_export, account: account, user: admin, export_format: 'raw_json')
        create(:dataset_export, account: create(:account), user: create(:user))

        get "/api/v1/accounts/#{account.id}/dataset_exports", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.pluck('id')).to eq([newer.id, older.id])
        expect(payload.first).to include('export_format' => 'raw_json', 'status' => 'completed', 'conversations_count' => 3)
        expect(payload.first['created_at']).to eq(newer.created_at.to_i)
        expect(payload.first['user']).to include('id' => admin.id)
      end
    end
  end
end
