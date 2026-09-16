require 'rails_helper'

RSpec.describe Telephony::RecordingFetchJob do
  let(:account) { create(:account) }
  let(:client) { instance_double(Telephony::ControllerClient) }
  let(:projection) do
    create(:telephony_call_projection, account: account, state: 'ended', ended_at: 1.minute.ago,
                                       recording_name: 'chatwoot-x', recording_state: 'stored')
  end

  before { allow(Telephony::ControllerClient).to receive(:new).and_return(client) }

  it 'downloads, attaches, deletes the remote file and marks fetched' do
    allow(client).to receive(:download_recording) do |_id, to:|
      File.binwrite(to, 'RIFF....WAVE')
      'audio/wav'
    end
    allow(client).to receive(:delete_recording)

    described_class.perform_now(projection.id)

    projection.reload
    expect(projection.recording).to be_attached
    expect(projection.recording_state).to eq('fetched')
    expect(client).to have_received(:delete_recording).with(projection.external_call_id)
  end

  it 'marks missing (terminal) when the controller answers 404 instead of retrying' do
    allow(client).to receive(:download_recording).and_raise(Telephony::ControllerClient::Error.new(404, 'no_recording'))

    described_class.perform_now(projection.id)

    expect(projection.reload.recording_state).to eq('missing')
    expect(projection.recording).not_to be_attached
  end

  it 'treats a PBX-side 404 (502 pbx_recording_404) as missing too' do
    allow(client).to receive(:download_recording).and_raise(Telephony::ControllerClient::Error.new(502, 'pbx_recording_404'))

    described_class.perform_now(projection.id)

    expect(projection.reload.recording_state).to eq('missing')
  end

  it 'retries transient errors and leaves the state for the sweep after giving up' do
    allow(client).to receive(:download_recording).and_raise(Telephony::ControllerClient::Error.new(503, 'pbx_unreachable'))

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(projection.id) }

    expect(projection.reload.recording_state).to eq('failed')
  end

  it 'does nothing for terminal states' do
    projection.update!(recording_state: 'missing')

    described_class.perform_now(projection.id)

    expect(projection.reload.recording_state).to eq('missing')
  end

  it 'only deletes the remote file when the recording is already attached (idempotent re-run)' do
    projection.recording.attach(io: StringIO.new('wav'), filename: 'a.wav', content_type: 'audio/wav')
    allow(client).to receive(:delete_recording).and_raise(Telephony::ControllerClient::Error.new(404, 'no_recording'))

    described_class.perform_now(projection.id)

    expect(projection.reload.recording_state).to eq('fetched')
  end
end
