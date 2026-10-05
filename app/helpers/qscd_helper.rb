module QscdHelper
  QSCD_IMAGES = {
    "cz_eid_2012" => "qscd/cz_eid_2012.jpg",
    "cz_eid_2018" => "qscd/cz_eid_2018.jpg",
    "ica_securestore" => "qscd/smart_card_or_token.svg",
    "monet_proid" => "qscd/smart_card_or_token.svg",
    "gemalto_idprime" => "qscd/smart_card.svg",
    "pkcs11_other" => "qscd/usb_token.svg"
  }.freeze

  QSCD_BADGES = {
    "eid_2024" => %i[mobile],
    "eid_2022" => %i[mobile],
    "eid_2021" => %i[card_reader],
    "eid_2013" => %i[unsupported],
    "dpb_2023" => %i[mobile],
    "dpb_2020" => %i[card_reader],
    "dpb_2014" => %i[unsupported],
    "cz_eid_2018" => %i[card_reader certificate],
    "cz_eid_2012" => %i[unsupported],
    "ica_securestore" => %i[driver],
    "monet_proid" => %i[driver],
    "gemalto_idprime" => %i[card_reader driver],
    "pkcs11_other" => %i[driver]
  }.freeze

  BADGE_CLASSES = {
    mobile: "bg-green-100 text-green-800",
    card_reader: "bg-yellow-100 text-yellow-800",
    driver: "bg-yellow-100 text-yellow-800",
    certificate: "bg-blue-100 text-blue-800",
    unsupported: "bg-red-100 text-red-800"
  }.freeze

  def qscd_image_path(qscd)
    QSCD_IMAGES.fetch(qscd.to_s, "qscd/#{qscd}.png")
  end

  # [[text, css classes], ...] for the compatibility badges of a QSCD card.
  def qscd_badges(qscd)
    QSCD_BADGES.fetch(qscd.to_s, []).map { |badge| [ t("qscd.badges.#{badge}"), BADGE_CLASSES.fetch(badge) ] }
  end

  # Which copy the onboarding steps use: Slovak documents (BOK), Czech ID card or a commercial card/token.
  def qscd_onboarding_variant(qscd)
    case User.qscd_group(qscd)
    when :cz_eid then "cz"
    when :tokens then "token"
    else "sk"
    end
  end
end
