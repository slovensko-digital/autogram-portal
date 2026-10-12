require "test_helper"
require "jwt"
require "openssl"
require_relative "../../../support/plan_limits_helper"

# POST /api/v1/bundles/:id/notify sends the invitations of a bundle created through the API.
class Api::V1::BundleNotificationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include PlanLimitsHelper

  setup do
    users(:one).update_column(:email, "owner@example.com")
    @tenant = tenants(:one)
    @key = OpenSSL::PKey::RSA.generate(2048)
    @tenant.update_columns(api_token_public_key: @key.public_to_pem, features: [ "api" ])

    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "notify without a body invites every active recipient who has not been invited yet" do
    bundle = create_api_bundle(recipients: %w[first second invited withdrawn].map { |name| { name: name, email: "#{name}@example.com" } })
    recipients = bundle.recipients.index_by(&:name)
    recipients["invited"].update!(notification_status: :notified, notified_at: Time.current)
    recipients["withdrawn"].withdraw!

    post notify_path(bundle), headers: api_headers

    assert_response :success
    assert_equal [ recipients["first"].uuid, recipients["second"].uuid ].sort, response.parsed_body["notified"].sort
    assert_equal [ { "id" => recipients["invited"].uuid, "reason" => "already_notified" } ], response.parsed_body["skipped"]
    assert_enqueued_jobs 2, only: Notification::RecipientSignatureRequestedJob
    assert recipients["first"].reload.sending?
    assert recipients["second"].reload.sending?
    assert recipients["withdrawn"].reload.not_notified?

    perform_enqueued_jobs only: Notification::RecipientSignatureRequestedJob
    assert_equal [ [ "first@example.com" ], [ "second@example.com" ] ], ActionMailer::Base.deliveries.map(&:to).sort
    assert recipients["first"].reload.notified?
    assert_not_nil recipients["first"].notified_at
  end

  test "notify with a list invites only the listed recipients" do
    bundle = create_api_bundle(recipients: [ { email: "chosen@example.com" }, { email: "later@example.com" } ])
    chosen = bundle.recipients.find_by!(email: "chosen@example.com")
    later = bundle.recipients.find_by!(email: "later@example.com")

    post notify_path(bundle), params: { recipients: [ chosen.uuid ] }, headers: api_headers, as: :json

    assert_response :success
    assert_equal({ "notified" => [ chosen.uuid ], "skipped" => [] }, response.parsed_body)
    assert_enqueued_with(job: Notification::RecipientSignatureRequestedJob, args: [ chosen ])
    assert_enqueued_jobs 1, only: Notification::RecipientSignatureRequestedJob
    assert chosen.reload.sending?
    assert later.reload.not_notified?
  end

  test "notify reports why each listed recipient was skipped" do
    bundle = create_api_bundle(recipients: %w[invited signed superseded withdrawn].map { |name| { name: name, email: "#{name}@example.com" } } + [ { name: "no_email" } ])
    recipients = bundle.recipients.index_by(&:name)
    recipients["invited"].update!(notification_status: :sending)
    recipients["signed"].signer_contracts.update_all(signed_at: Time.current)
    recipients["withdrawn"].withdraw!
    author_proxy = Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: users(:one))
    # Last: adding a recipient recomputes the signing rule, which lifts a superseded state it does not justify.
    recipients["superseded"].signer_contracts.update_all(superseded_at: Time.current)
    other_bundle_recipient = create_api_bundle(recipients: [ { email: "elsewhere@example.com" } ]).recipients.sole
    unknown = SecureRandom.uuid

    listed = [ recipients["invited"], recipients["signed"], recipients["superseded"], recipients["withdrawn"], recipients["no_email"] ].map(&:uuid)
    listed += [ author_proxy.uuid, other_bundle_recipient.uuid, unknown, "not-a-uuid" ]

    assert_no_enqueued_jobs do
      post notify_path(bundle), params: { recipients: listed }, headers: api_headers, as: :json
    end

    assert_response :success
    assert_equal [], response.parsed_body["notified"]
    assert_equal [
      { "id" => recipients["invited"].uuid, "reason" => "already_notified" },
      { "id" => recipients["signed"].uuid, "reason" => "signed" },
      { "id" => recipients["superseded"].uuid, "reason" => "superseded" },
      { "id" => recipients["withdrawn"].uuid, "reason" => "withdrawn" },
      { "id" => recipients["no_email"].uuid, "reason" => "no_email" },
      { "id" => author_proxy.uuid, "reason" => "not_found" },
      { "id" => other_bundle_recipient.uuid, "reason" => "not_found" },
      { "id" => unknown, "reason" => "not_found" },
      { "id" => "not-a-uuid", "reason" => "not_found" }
    ], response.parsed_body["skipped"]
    assert recipients["no_email"].reload.not_notified?
    assert other_bundle_recipient.reload.not_notified?
  end

  test "notify never sends a second invitation to a recipient" do
    bundle = create_api_bundle(recipients: [ { email: "once@example.com" } ])
    recipient = bundle.recipients.sole

    post notify_path(bundle), headers: api_headers
    assert_equal [ recipient.uuid ], response.parsed_body["notified"]
    assert_enqueued_jobs 1, only: Notification::RecipientSignatureRequestedJob

    assert_no_enqueued_jobs do
      post notify_path(bundle), headers: api_headers
    end
    assert_response :success
    assert_equal({ "notified" => [], "skipped" => [ { "id" => recipient.uuid, "reason" => "already_notified" } ] }, response.parsed_body)

    perform_enqueued_jobs
    assert_no_enqueued_jobs do
      post notify_path(bundle), params: { recipients: [ recipient.uuid, recipient.uuid ] }, headers: api_headers, as: :json
    end
    assert_equal({ "notified" => [], "skipped" => [ { "id" => recipient.uuid, "reason" => "already_notified" } ] }, response.parsed_body)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "notify sends a federated recipient's invitation to its portal" do
    portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    )
    bundle = create_api_bundle(recipients: [ { email: "recipient@partner.example", portalInstanceId: portal_instance.uuid } ])
    recipient = bundle.recipients.sole

    post notify_path(bundle), headers: api_headers

    assert_response :success
    assert_equal [ recipient.uuid ], response.parsed_body["notified"]
    assert_enqueued_with(job: Federation::SendRequestInvitationJob, args: [ recipient ])
    assert_no_enqueued_jobs only: Notification::RecipientSignatureRequestedJob
  end

  test "notify reports the plan limit and sends nothing when the documents do not fit" do
    bundle = create_api_bundle(recipients: [ { email: "first@example.com" }, { email: "second@example.com" } ])

    with_plan_limits("BASIC_MONTHLY_SIGNATURE_REQUESTS" => "0") do
      assert_no_enqueued_jobs do
        post notify_path(bundle), headers: api_headers
      end
    end

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "limit_exceeded", body["code"]
    assert_equal "signature_requests", body["limit"]
    assert_equal [ PlanLimits::Exceeded.new(limit: :signature_requests, max: 0, used: 0).message ], body["errors"]
    assert_equal [], body["notified"]
    assert_equal [], body["skipped"]
    assert bundle.recipients.all?(&:not_notified?)
    assert_equal 0, @tenant.usage_of(:signature_requests)
  end

  test "notify rejects a recipients value that is not a list" do
    bundle = create_api_bundle(recipients: [ { email: "first@example.com" } ])

    assert_no_enqueued_jobs do
      post notify_path(bundle), params: { recipients: bundle.recipients.sole.uuid }, headers: api_headers, as: :json
    end

    assert_response :bad_request
    assert bundle.recipients.sole.not_notified?
  end

  test "notify of an unknown bundle is not found" do
    post "/api/v1/bundles/#{SecureRandom.uuid}/notify", headers: api_headers

    assert_response :not_found
    assert_equal({ "error" => "Bundle not found" }, response.parsed_body)
  end

  test "notify cannot reach another organization's bundle" do
    other = tenants(:two)
    other_key = OpenSSL::PKey::RSA.generate(2048)
    other.update_columns(api_token_public_key: other_key.public_to_pem, features: [ "api" ])
    bundle = create_api_bundle(recipients: [ { email: "foreign@example.com" } ], tenant: other, key: other_key)

    assert_no_enqueued_jobs do
      post notify_path(bundle), headers: api_headers
    end

    assert_response :not_found
    assert_equal({ "error" => "Bundle not found" }, response.parsed_body)
    assert bundle.recipients.sole.not_notified?
  end

  test "notify requires an API token" do
    bundle = create_api_bundle(recipients: [ { email: "first@example.com" } ])

    post notify_path(bundle)

    assert_response :unauthorized
    assert bundle.recipients.sole.not_notified?
  end

  private

  def notify_path(bundle)
    "/api/v1/bundles/#{bundle.uuid}/notify"
  end

  def create_api_bundle(recipients:, tenant: @tenant, key: @key)
    post "/api/v1/bundles",
         params: {
           id: SecureRandom.uuid,
           contracts: [
             {
               id: SecureRandom.uuid,
               allowedMethods: [ "qes" ],
               documents: [ { filename: "contract.txt", content: Base64.strict_encode64("Sample text content"), contentType: "text/plain;base64" } ],
               signatureParameters: { format: "XAdES", container: "ASiC_E" }
             }
           ],
           recipients: recipients
         },
         headers: api_headers(tenant: tenant, key: key),
         as: :json
    assert_response :created, -> { response.body }

    Bundle.find_by!(uuid: response.parsed_body.fetch("id"))
  end

  def api_headers(tenant: @tenant, key: @key)
    token = JWT.encode({ sub: tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, key, "RS256")
    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end
