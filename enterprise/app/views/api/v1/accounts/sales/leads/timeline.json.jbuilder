json.payload do
  json.entries @timeline[:entries] do |entry|
    json.merge! entry.except(:created_at)
    json.created_at entry[:created_at].to_i
  end
  json.next_before @timeline[:next_before]&.to_i
end
