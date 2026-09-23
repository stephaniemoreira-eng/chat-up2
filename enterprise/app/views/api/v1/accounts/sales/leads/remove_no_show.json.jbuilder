json.payload do
  json.partial! 'api/v1/models/sales_lead', formats: [:json], resource: @lead
end
