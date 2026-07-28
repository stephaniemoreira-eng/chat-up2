json.payload do
  json.array! @stages do |stage|
    json.partial! 'api/v1/models/sales_stage', formats: [:json], resource: stage
  end
end
