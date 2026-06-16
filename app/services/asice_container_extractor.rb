require "zip"

class AsiceContainerExtractor
  ExtractedDocument = Struct.new(:blob, :xdcf, keyword_init: true)

  def initialize(document)
    @document = document
  end

  def extract_documents
    with_archive do |archive|
      archive.filter_map do |entry|
        next unless extractable_entry?(entry)

        content = entry.get_input_stream.read
        next if content.blank?

        ExtractedDocument.new(
          blob: ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(content),
            filename: File.basename(entry.name),
            content_type: extracted_content_type(entry.name, content)
          ),
          xdcf: File.extname(entry.name).casecmp(".xdcf").zero?
        )
      end
    end
  end

  def container_content
    @container_content ||= begin
      if pending_upload
        pending_upload.tempfile.binmode
        pending_upload.tempfile.rewind
        pending_upload.tempfile.read
      else
        document.blob.download
      end
    end
  end

  private

  attr_reader :document

  def with_archive
    archive_path = Tempfile.create([ "asice-container", ".asice" ])
    archive_path.binmode
    archive_path.write(container_content)
    archive_path.flush

    Zip::File.open(archive_path.path) do |archive|
      yield archive.entries
    end
  ensure
    archive_path&.close
  end

  def pending_upload
    attachment_change = document.attachment_changes["blob"]
    attachable = attachment_change&.attachable
    return unless attachable.respond_to?(:tempfile)

    attachable
  end

  def extractable_entry?(entry)
    return false if entry.directory?
    return false if entry.name.start_with?("META-INF/")

    basename = File.basename(entry.name)
    return false if basename == "mimetype"

    true
  end

  def extracted_content_type(entry_name, content)
    return "application/vnd.gov.sk.xmldatacontainer+xml" if File.extname(entry_name).casecmp(".xdcf").zero?

    Marcel::MimeType.for(StringIO.new(content), name: entry_name)
  end
end
