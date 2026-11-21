require "test_helper"

class ApiTokenUsesCleanupJobTest < ActiveJob::TestCase
  test "deletes uses of API tokens that have expired" do
    expired = ApiTokenUse.create!(tenant: tenants(:one), jti: SecureRandom.hex(16), expires_at: 1.minute.ago)
    valid = ApiTokenUse.create!(tenant: tenants(:one), jti: SecureRandom.hex(16), expires_at: 1.minute.from_now)

    ApiTokenUsesCleanupJob.perform_now

    assert_not ApiTokenUse.exists?(expired.id)
    assert ApiTokenUse.exists?(valid.id)
  end
end
