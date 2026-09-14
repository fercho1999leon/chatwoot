json.meta do
  json.count @calls_count
  json.current_page @calls.current_page
  json.total_pages @calls.total_pages
end

json.payload do
  json.array! @calls do |call|
    json.partial! 'api/v1/models/telephony_call_history', formats: [:json], call: call
  end
end
