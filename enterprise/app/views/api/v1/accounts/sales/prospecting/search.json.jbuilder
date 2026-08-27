json.search_id @search.id
json.payload do
  json.array! @results do |result|
    json.id result.id
    json.place_id result.place_id
    json.name result.name
    json.address result.address
    json.phone_number result.phone_number
    json.website result.website
    json.rating result.rating
    json.user_ratings_total result.user_ratings_total
  end
end
