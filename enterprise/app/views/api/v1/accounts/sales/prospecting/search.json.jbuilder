json.payload do
  json.array! @results do |result|
    json.place_id result[:place_id]
    json.name result[:name]
    json.address result[:address]
    json.phone_number result[:phone_number]
    json.website result[:website]
  end
end
