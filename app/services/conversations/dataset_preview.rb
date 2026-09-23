# Counts what an export would produce, without generating any file, so administrators can
# check their settings before running the job. Only the most recent PREVIEW_SIZE
# conversations are built, which keeps the request cheap on large accounts.
class Conversations::DatasetPreview
  PREVIEW_SIZE = 100

  def initialize(account, user, params)
    @account = account
    @user = user
    @params = params
    @options = params[:options].to_h
  end

  def perform
    selection = Conversations::DatasetSelection.new(@account, @user, @params)
    analyzed = build_samples(selection)

    {
      matching_count: selection.scope.count,
      limit: selection.limit,
      analyzed_count: analyzed,
      kept_count: @kept,
      dropped: @dropped,
      sample: @sample
    }
  end

  private

  def build_samples(selection)
    @kept = 0
    @dropped = Hash.new(0)
    cap = [selection.limit, PREVIEW_SIZE].min

    selection.each_conversation(cap: cap) do |conversation|
      builder = Conversations::DatasetBuilder.new(conversation, @options)
      sample = builder.chat_sample
      if sample
        @kept += 1
        @sample ||= sample
      else
        @dropped[builder.drop_reason] += 1
      end
    end
  end
end
