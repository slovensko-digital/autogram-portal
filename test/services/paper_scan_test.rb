require "test_helper"

class PaperScanTest < ActiveSupport::TestCase
  test "photos are combined into one PDF page each, in order" do
    pdf = PaperScan.combine([ [ file_fixture("paper-page.jpg").binread, "image/jpeg" ], [ file_fixture("paper-page.png").binread, "image/png" ] ])
    assert pdf.start_with?("%PDF")
    assert_equal 2, PaperScan.page_count(pdf)
  end

  test "the page count of something that is not a readable PDF is unknown" do
    assert_nil PaperScan.page_count("%PDF-1.4 zmluva.pdf")
  end
end
