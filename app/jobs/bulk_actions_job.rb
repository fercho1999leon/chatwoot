class BulkActionsJob < ApplicationJob
  include DateRangeHelper

  queue_as :medium
  attr_accessor :records

  MODEL_TYPE = ['Conversation'].freeze

  def perform(account:, params:, user:)
    @account = account
    @user = user
    Current.user = user
    @params = params
    @records = records_to_updated(params[:ids])
    bulk_update
  ensure
    Current.reset
  end

  def bulk_update
    return bulk_delete if @params[:action_name] == 'delete'

    bulk_remove_labels
    bulk_conversation_update
  end

  # Cada conversación pasa por el mismo servicio que el borrado individual (rastro de correos IMAP,
  # DeleteObjectJob con el usuario que lo pidió). El controlador ya comprobó destroy? (administrador).
  def bulk_delete
    records.each do |conversation|
      ::Conversations::DeleteService.new(conversation: conversation, user: @user, ip: nil).perform
    end
  end

  def bulk_conversation_update
    params = available_params(@params)
    records.each do |conversation|
      bulk_add_labels(conversation)
      bulk_snoozed_until(conversation)
      conversation.update(params) if params
    end
  end

  def bulk_remove_labels
    records.each do |conversation|
      remove_labels(conversation)
    end
  end

  # status en blanco = «sin cambio»; priority en blanco = «sin prioridad» (None), por eso se conserva.
  def available_params(params)
    return unless params[:fields]

    params[:fields].delete_if { |key, value| value.nil? && key == 'status' }
  end

  def bulk_add_labels(conversation)
    conversation.add_labels(@params[:labels][:add]) if @params[:labels] && @params[:labels][:add]
  end

  def bulk_snoozed_until(conversation)
    conversation.snoozed_until = parse_date_time(@params[:snoozed_until].to_s) if @params[:snoozed_until]
  end

  def remove_labels(conversation)
    return unless @params[:labels] && @params[:labels][:remove]

    labels = conversation.label_list - @params[:labels][:remove]
    conversation.update(label_list: labels)
  end

  def records_to_updated(ids)
    current_model = @params[:type].camelcase
    return unless MODEL_TYPE.include?(current_model)

    scope = current_model.constantize.where(account_id: @account.id, display_id: ids)
    Conversations::PermissionFilterService.new(scope, @user, @account).perform
  end
end
