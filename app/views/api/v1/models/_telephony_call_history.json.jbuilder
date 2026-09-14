# Misma forma que enterprise/app/views/api/v1/models/_call.json.jbuilder (CallListItem.vue).
json.id call.id
json.call_id call.external_call_id
json.provider 'asterisk'
json.status call.display_status
json.direction call.direction
json.duration_seconds call.duration_seconds
json.end_reason call.end_reason
json.started_at call.answered_at&.to_i
json.created_at call.created_at.to_i
json.message_id call.message_id
json.recording_url call.recording_url
json.transcript nil
json.answered_by call.answered_by
json.previous_user_id call.previous_user_id

json.conversation do
  json.id call.conversation_id
  json.display_id call.conversation.display_id
end

json.inbox do
  json.id call.inbox_id
  json.name call.inbox&.name
  json.channel_type call.inbox&.channel_type
  json.medium nil
end

if call.user
  json.agent do
    json.id call.user.id
    json.name call.user.available_name
    json.avatar call.user.avatar_url
  end
else
  json.agent nil
end

contact = call.conversation.contact
if contact
  json.contact do
    json.id contact.id
    json.name contact.name
    json.phone_number contact.phone_number
    json.avatar contact.avatar_url
  end
else
  json.contact nil
end
