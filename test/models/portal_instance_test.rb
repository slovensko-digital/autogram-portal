# == Schema Information
#
# Table name: portal_instances
#
#  id                    :bigint           not null, primary key
#  allowed_email_domains :string           default([]), not null, is an Array
#  base_url              :string           not null
#  capabilities          :jsonb            not null
#  issuer                :string           not null
#  last_verified_at      :datetime
#  metadata              :jsonb            not null
#  name                  :string           not null
#  outbound_kid          :string
#  public_key_pem        :text             not null
#  status                :string           default("verified"), not null
#  uuid                  :uuid             not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_portal_instances_on_issuer  (issuer) UNIQUE
#  index_portal_instances_on_status  (status)
#  index_portal_instances_on_uuid    (uuid) UNIQUE
#
require "test_helper"
require "openssl"

class PortalInstanceTest < ActiveSupport::TestCase
  test "normalizes URLs and email domains" do
    portal_instance = build_portal_instance(
      base_url: "https://example.com/",
      issuer: "https://issuer.example.com/",
      allowed_email_domains: [ " Example.COM ", "example.com" ]
    )

    assert portal_instance.valid?
    assert_equal "https://example.com", portal_instance.base_url
    assert_equal "https://issuer.example.com", portal_instance.issuer
    assert_equal [ "example.com" ], portal_instance.allowed_email_domains
  end

  test "rejects local URLs" do
    portal_instance = build_portal_instance(base_url: "https://localhost")

    assert_not portal_instance.valid?
    assert_includes portal_instance.errors[:base_url], "cannot target local or private addresses"
  end

  private

  def build_portal_instance(**attributes)
    PortalInstance.new({
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    }.merge(attributes))
  end
end
