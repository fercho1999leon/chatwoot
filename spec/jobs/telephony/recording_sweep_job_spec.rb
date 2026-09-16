require 'rails_helper'

RSpec.describe Telephony::RecordingSweepJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }

  def projection(state:, ended_at:, name: 'chatwoot-x', attached: false)
    p = create(:telephony_call_projection, account: account, state: 'ended', ended_at: ended_at, recording_name: name, recording_state: state)
    p.recording.attach(io: StringIO.new('wav'), filename: 'a.wav', content_type: 'audio/wav') if attached
    p
  end

  it 're-enqueues the fetch for stored/failed recordings without attachment inside the window' do
    stale_stored = projection(state: 'stored', ended_at: 2.hours.ago)
    failed = projection(state: 'failed', ended_at: 1.day.ago)
    projection(state: 'stored', ended_at: 2.minutes.ago)                 # RecordingFetchJob todavía está en ello
    projection(state: 'failed', ended_at: 8.days.ago)                    # fuera de la ventana
    projection(state: 'missing', ended_at: 1.hour.ago)                   # terminal
    projection(state: 'stored', ended_at: 1.hour.ago, attached: true)    # ya recogida (estado rezagado)
    projection(state: 'failed', ended_at: 1.hour.ago, name: nil)         # sin archivo que buscar

    expect { described_class.perform_now }.to have_enqueued_job(Telephony::RecordingFetchJob).exactly(2).times
    expect(Telephony::RecordingFetchJob).to have_been_enqueued.with(stale_stored.id)
    expect(Telephony::RecordingFetchJob).to have_been_enqueued.with(failed.id)
  end

  it 'scopes to one account when asked' do
    mine = projection(state: 'failed', ended_at: 1.hour.ago)
    create(:telephony_call_projection, account: create(:account), state: 'ended', ended_at: 1.hour.ago,
                                       recording_name: 'x', recording_state: 'failed')

    expect { described_class.perform_now(account_id: account.id) }.to have_enqueued_job(Telephony::RecordingFetchJob).with(mine.id).once
  end
end
