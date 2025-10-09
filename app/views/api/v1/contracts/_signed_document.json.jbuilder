json.download_url rails_blob_url(signed_document.blob)
json.content_type signed_document.blob.content_type
json.filename signed_document.blob.filename.to_s
json.file_size signed_document.blob.byte_size
json.checksum signed_document.blob.checksum
json.signed_at signed_document.created_at
