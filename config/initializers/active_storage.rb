# Signing pages embedded by integrators show the PDF in a nested iframe served by
# Active Storage (the disk service in development and staging, the proxy in
# production), so these files have to allow cross-origin framing like the signing
# pages. Their URLs are signed and they serve only files.
Rails.application.config.to_prepare do
  [ ActiveStorage::DiskController, ActiveStorage::Blobs::ProxyController ].each do |controller|
    controller.include AllowsCrossOriginFraming
    controller.before_action :allow_cross_origin_framing, only: :show
  end
end
