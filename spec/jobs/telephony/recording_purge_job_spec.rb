require 'rails_helper'

RSpec.describe Telephony::RecordingPurgeJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Telephony::ControllerClient, delete_recording: { 'ok' => true }) }

  before do
    allow(Telephony::ControllerClient).to receive(:new).and_return(client)
    create(:telephony_pbx, account: account, recording_retention_days: 30)
  end

  def projection(state:, created_at:, attached: false)
    p = create(:telephony_call_projection, account: account, state: 'ended', created_at: created_at, ended_at: created_at,
                                           recording_name: 'chatwoot-x', recording_state: state)
    p.recording.attach(io: StringIO.new('wav'), filename: 'a.wav', content_type: 'audio/wav') if attached
    p
  end

  it 'purges old attached recordings and also deletes never-fetched ones from the PBX' do
    attached = projection(state: 'fetched', created_at: 40.days.ago, attached: true)
    remote_only = projection(state: 'failed', created_at: 40.days.ago)
    recent = projection(state: 'fetched', created_at: 2.days.ago, attached: true)
    already_missing = projection(state: 'missing', created_at: 40.days.ago)

    described_class.perform_now

    expect(attached.reload.recording_state).to eq('purged')
    expect(remote_only.reload.recording_state).to eq('purged')
    expect(client).to have_received(:delete_recording).with(remote_only.external_call_id).once
    expect(client).not_to have_received(:delete_recording).with(attached.external_call_id)
    expect(recent.reload.recording_state).to eq('fetched')
    expect(already_missing.reload.recording_state).to eq('missing')
  end

  it 'keeps purging locally when the PBX cannot be reached' do
    remote_only = projection(state: 'stored', created_at: 40.days.ago)
    allow(client).to receive(:delete_recording).and_raise(Telephony::ControllerClient::Error.new(503, 'pbx_unreachable'))

    described_class.perform_now

    expect(remote_only.reload.recording_state).to eq('purged')
  end
end
