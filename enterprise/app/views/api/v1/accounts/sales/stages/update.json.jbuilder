json.payload do
  json.partial! 'api/v1/models/sales_stage', formats: [:json], resource: @stage
end
