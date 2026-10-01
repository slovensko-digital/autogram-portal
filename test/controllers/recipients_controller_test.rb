require "test_helper"
require "openssl"

class RecipientsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers
  include ActiveJob::TestHelper

  tests RecipientsController

  setup do
    @user = users(:one)
    @user.update_column(:email, "owner@example.com")
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }

    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "index renders trusted portal selection" do
    portal_instance = create_portal_instance(name: "Partner Portal")

    get :index, params: { bundle_id: bundles(:one).uuid }

    assert_response :success
    assert_select "select[name='recipient[portal_instance_uuid]']"
    assert_select "option[value='#{portal_instance.uuid}']", text: "Partner Portal"
  end

  test "create stores a federated recipient via portal selection" do
    portal_instance = create_portal_instance

    post :create, params: {
      bundle_id: bundles(:one).uuid,
      recipient: {
        email: "recipient@partner.example",
        portal_instance_uuid: portal_instance.uuid
      }
    }

    assert_response :success

    recipient = bundles(:one).recipients.find_by!(email: "recipient@partner.example")
    assert_equal portal_instance, recipient.portal_instance
    assert recipient.federated_recipient?
    assert_select "[role='status']", text: I18n.t("recipients.index.added", recipient: recipient.display_name)
    assert_select "form[data-controller='form-submit'][data-form-submit-pending-text-value=?]", I18n.t("actions.adding")
  end

  test "create stores normalized mobile phone" do
    post :create, params: {
      bundle_id: bundles(:one).uuid,
      recipient: {
        email: "recipient@example.com",
        mobile_phone: "00421 901 234 567"
      }
    }

    assert_response :success

    recipient = bundles(:one).recipients.find_by!(email: "recipient@example.com")
    assert_equal "+421901234567", recipient.mobile_phone
  end

  test "create keeps validation feedback inline without showing success" do
    post :create, params: {
      bundle_id: bundles(:one).uuid,
      recipient: { email: "not-an-email" }
    }

    assert_response :success
    assert_select ".bg-red-50", text: /Email/
    assert_select "[role='status']", count: 0
  end

  test "notify queues an invitation and reports that sending has started" do
    recipient = bundles(:one).recipients.create!(email: "invitee@example.com")

    assert_enqueued_with(job: Notification::RecipientSignatureRequestedJob, args: [ recipient ]) do
      post :notify, params: { bundle_id: bundles(:one).uuid, id: recipient.uuid }
    end

    assert_response :success
    assert recipient.reload.sending?
    assert_select "[role='status']", text: I18n.t("recipients.index.invitation_sending", recipient: recipient.display_name)
  end

  test "notify reports an error when the recipient is no longer eligible" do
    recipient = bundles(:one).recipients.create!(email: "already-sending@example.com", notification_status: :sending)

    assert_no_enqueued_jobs do
      post :notify, params: { bundle_id: bundles(:one).uuid, id: recipient.uuid }
    end

    assert_response :success
    assert_select "[role='alert']", text: I18n.t("recipients.index.invitation_failed", recipient: recipient.display_name)
    assert_select "[role='status']", count: 0
  end

  test "destroy withdraws the request and reports success" do
    recipient = bundles(:one).recipients.create!(email: "removed@example.com")

    delete :destroy, params: { bundle_id: bundles(:one).uuid, id: recipient.uuid }

    assert_response :success
    assert recipient.reload.withdrawn?
    assert_select "[role='status']", text: I18n.t("recipients.index.withdrawn", recipient: recipient.display_name)

    delete :destroy, params: { bundle_id: bundles(:one).uuid, id: recipient.uuid }

    assert_response :success
    assert_select "[role='alert']", text: I18n.t("recipients.index.withdraw_failed", recipient: recipient.display_name)
    assert_select "[role='status']", count: 0
  end

  test "admin cannot create recipients in another tenant bundle" do
    @user.update_column(:features, [ "admin" ])
    foreign_bundle = bundles(:two)
    foreign_bundle.update_column(:uuid, SecureRandom.uuid)

    assert_no_difference -> { Recipient.count } do
      post :create, params: { bundle_id: foreign_bundle.uuid, recipient: { email: "foreign@example.com" } }
    end

    assert_response :not_found
  end

  test "recipient management in another own tenant keeps tenant guidance" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: @user)
    session[:current_tenant_id] = tenants(:one).id
    foreign_bundle = bundles(:two)
    foreign_bundle.update_column(:uuid, SecureRandom.uuid)

    assert_no_difference -> { Recipient.count } do
      post :create, params: { bundle_id: foreign_bundle.uuid, recipient: { email: "foreign@example.com" } }
    end

    assert_redirected_to dashboard_path
    assert_equal I18n.t("tenants.alerts.other_tenant_record", name: tenants(:two).name), flash[:alert]
    assert_equal tenants(:one).id, session[:current_tenant_id]
  end

  test "recipient lookup remains scoped to its parent bundle" do
    foreign_bundle = bundles(:two)
    foreign_bundle.update_column(:uuid, SecureRandom.uuid)
    recipient = foreign_bundle.recipients.create!(email: "foreign@example.com")

    delete :destroy, params: { bundle_id: bundles(:one).uuid, id: recipient.uuid }

    assert_response :not_found
    assert_not recipient.reload.withdrawn?
  end

  private

  def create_portal_instance(**attributes)
    PortalInstance.create!({
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    }.merge(attributes))
  end
end
