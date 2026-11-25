require "test_helper"

class PaperSignaturesHelperTest < ActionView::TestCase
  test "the intro ends with one period also when the sender's name ends with one" do
    I18n.with_locale(:sk) do
      assert_equal "Vytlačte dokument, podpíšte ho perom a nahrajte sken alebo fotky strán. Podpis potom skontroluje odosielateľ, Firma ABC, s. r. o.",
        paper_signature_intro("Firma ABC, s. r. o.")
      assert_equal "Vytlačte dokument, podpíšte ho perom a nahrajte sken alebo fotky strán. Podpis potom skontroluje odosielateľ, Firma ABC.",
        paper_signature_intro("Firma ABC")
    end

    I18n.with_locale(:en) do
      assert_equal "Print the document, sign it with a pen and upload a scan or photos of the pages. The sender, Firma ABC, s. r. o., then checks the signature.",
        paper_signature_intro("Firma ABC, s. r. o.")
    end
  end
end
