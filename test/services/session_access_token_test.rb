require "test_helper"

class SessionAccessTokenTest < ActiveSupport::TestCase
  test "accepts token for matching contract and session" do
    token = SessionAccessToken.generate(
      contract: contracts(:one),
      session: avm_sessions(:one),
      expires_at: 10.minutes.from_now
    )

    assert SessionAccessToken.valid?(token: token, contract: contracts(:one), session: avm_sessions(:one))
  end

  test "rejects token for different session" do
    token = SessionAccessToken.generate(
      contract: contracts(:one),
      session: avm_sessions(:one),
      expires_at: 10.minutes.from_now
    )

    assert_not SessionAccessToken.valid?(token: token, contract: contracts(:one), session: avm_sessions(:two))
  end

  test "rejects expired token" do
    token = SessionAccessToken.generate(
      contract: contracts(:one),
      session: avm_sessions(:one),
      expires_at: 1.minute.ago
    )

    assert_not SessionAccessToken.valid?(token: token, contract: contracts(:one), session: avm_sessions(:one))
  end

  test "rejects token for withdrawn recipient session" do
    token = SessionAccessToken.generate(
      contract: contracts(:one),
      session: avm_sessions(:one),
      expires_at: 10.minutes.from_now
    )

    withdrawn_session = Struct.new(:id, :recipient).new(
      avm_sessions(:one).id,
      Struct.new(:withdrawn?).new(true)
    )

    assert_not SessionAccessToken.valid?(token: token, contract: contracts(:one), session: withdrawn_session)
  end
end
