# Signing pages embedded by integrators show the source PDF in a nested iframe. Files
# from the disk service (development, staging) come from the portal itself, so they
# have to allow cross-origin framing like the signing pages; cloud services (production)
# send no framing headers. Disk URLs are signed and expire, and they serve only files.
Rails.application.config.to_prepare do
  ActiveStorage::DiskController.include AllowsCrossOriginFraming
  ActiveStorage::DiskController.before_action :allow_cross_origin_framing, only: :show
end
