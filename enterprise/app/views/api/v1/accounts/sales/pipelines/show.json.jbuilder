json.payload do
  json.partial! 'api/v1/models/sales_pipeline', formats: [:json], resource: @pipeline
end
