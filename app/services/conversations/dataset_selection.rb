# Resolves which conversations a dataset export covers, and loads them in batches with
# everything Conversations::DatasetBuilder needs. Shared by the export job and its preview.
class Conversations::DatasetSelection
  MAX_CONVERSATIONS = 50_000
  BATCH_SIZE = 200

  def initialize(account, user, params)
    @account = account
    @user = user
    @params = params
  end

  def scope
    return ::Conversations::FilterService.new(@params, @user, @account).filtered_conversations if @params[:payload].present?

    scope = @account.conversations.where(status: @params[:status].presence || :resolved)
    scope = scope.where(inbox_id: @params[:inbox_ids]) if @params[:inbox_ids].present?
    scope = scope.where(created_at: @params[:since]..) if @params[:since].present?
    scope = scope.where(created_at: ..@params[:until]) if @params[:until].present?
    scope
  end

  def limit
    [@params[:limit].presence&.to_i || MAX_CONVERSATIONS, MAX_CONVERSATIONS].min
  end

  # Newest first, in batches, so a large export never loads every thread at once.
  def each_conversation(cap: limit)
    ids = scope.reorder(created_at: :desc).limit(cap).pluck(:id)

    ids.each_slice(BATCH_SIZE) do |batch_ids|
      batch = Conversation.where(id: batch_ids)
                          .preload(:inbox, :contact, :csat_survey_response, messages: [:sender, :attachments])
                          .index_by(&:id)
      batch_ids.each { |id| yield batch[id] }
    end

    ids.size
  end
end
