json.payload do
  json.partial! 'api/v1/models/sales_prospecting_config', formats: [:json], resource: @config
end
