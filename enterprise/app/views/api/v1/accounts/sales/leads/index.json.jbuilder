json.payload do
  json.array! @leads do |lead|
    json.partial! 'api/v1/models/sales_lead', formats: [:json], resource: lead
  end
end
