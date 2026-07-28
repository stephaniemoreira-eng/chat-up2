json.id resource.id
json.name resource.name
json.description resource.description
json.position resource.position
json.active resource.active
json.is_default resource.is_default
json.stages resource.stages do |stage|
  json.partial! 'api/v1/models/sales_stage', formats: [:json], resource: stage
end
json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
