json.id dataset_export.id
json.export_format dataset_export.export_format
json.status dataset_export.status
json.conversations_count dataset_export.conversations_count
json.created_at dataset_export.created_at.to_i
json.file_url dataset_export.file_url
json.file_name dataset_export.file.filename.to_s if dataset_export.file.attached?
json.file_size dataset_export.file.byte_size if dataset_export.file.attached?
json.user dataset_export.user&.slice(:id, :name, :email)
