json.payload do
  json.array! @pipelines do |pipeline|
    json.partial! 'api/v1/models/sales_pipeline', formats: [:json], resource: pipeline
  end
end
