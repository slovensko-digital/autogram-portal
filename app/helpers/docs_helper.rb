module DocsHelper
  SCREENSHOTS_DIR = "docs/screenshots".freeze
  SCREENSHOT_DIMENSIONS = Concurrent::Map.new

  # Colors of the statuses the app shows in its lists, so the guide looks the same.
  STATUS_BADGE_CLASSES = {
    yellow: "bg-yellow-100 text-yellow-800",
    green: "bg-green-100 text-green-800",
    red: "bg-red-100 text-red-800",
    gray: "bg-gray-100 text-gray-700",
    amber: "bg-amber-100 text-amber-800"
  }.freeze

  def docs_status_badge(label, color)
    tag.span(label, class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap #{STATUS_BADGE_CLASSES.fetch(color)}")
  end

  # A guide section: a region named by its heading. The contents link to it without Turbo, so the
  # browser moves focus here (tabindex), and it ends with a link back to the contents.
  def docs_section(anchor, title:, icon:, color:, &block)
    tag.section(id: anchor, tabindex: "-1", "aria-labelledby": "#{anchor}-title",
                class: "scroll-mt-8 rounded-lg focus-visible:outline-2 focus-visible:outline-offset-8 focus-visible:outline-blue-600") do
      safe_join([
        render("docs/section_header", id: "#{anchor}-title", title: title, icon: icon, color: color),
        capture(&block),
        render("docs/back_to_contents")
      ])
    end
  end

  # Screen reader hint for links opening a new tab.
  def docs_new_tab_hint
    tag.span(" #{t('docs.index.opens_in_new_tab')}", class: "sr-only")
  end

  # Screenshot of the user guide in the current locale (default locale when missing), taken by
  # test/user_guide/screenshots.rb. The images are taken at 2x, so they are shown at half their size.
  def docs_screenshot(name, alt:, caption:)
    path = [ I18n.locale, I18n.default_locale ].uniq
      .map { |locale| "/#{SCREENSHOTS_DIR}/#{locale}/#{name}.webp" }
      .find { |candidate| Rails.public_path.join(candidate.delete_prefix("/")).exist? }
    return if path.nil?

    width, height = docs_screenshot_dimensions(path)
    # Narrow screenshots keep their size instead of being blown up to the full column.
    tag.figure(class: "mt-6") do
      safe_join([
        link_to(path, target: "_blank", rel: "noopener", class: "mx-auto block w-fit max-w-full overflow-hidden rounded-xl border border-gray-200 bg-gray-50 shadow-sm hover:border-blue-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600") do
          image_tag(path, alt: alt, width: width, height: height, loading: "lazy", decoding: "async", class: "block h-auto max-w-full") +
            tag.span(" #{t('docs.index.screenshot_full_size')}", class: "sr-only")
        end,
        tag.figcaption(caption, class: "mt-2 text-center text-sm text-gray-600")
      ])
    end
  end

  private

  # Width and height in CSS pixels, read from the WebP header (lossy VP8, lossless VP8L or extended VP8X).
  def docs_screenshot_dimensions(path)
    file = Rails.public_path.join(path.delete_prefix("/"))
    SCREENSHOT_DIMENSIONS.compute_if_absent([ path, file.mtime.to_i ]) do
      header = file.binread(30)
      width, height = case header[12, 4]
      when "VP8 " then header[26, 4].unpack("v2").map { |value| value & 0x3fff }
      when "VP8L"
        bits = header[21, 4].unpack1("V")
        [ (bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1 ]
      when "VP8X" then [ header[24, 3], header[27, 3] ].map { |bytes| "#{bytes}\0".unpack1("V") + 1 }
      end
      width && height ? [ width / 2, height / 2 ] : [ nil, nil ]
    end
  end
end
