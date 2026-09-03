json.payload do
  json.array! @configs do |config|
    json.partial! 'api/v1/models/sales_prospecting_config', formats: [:json], resource: config
  end
end
