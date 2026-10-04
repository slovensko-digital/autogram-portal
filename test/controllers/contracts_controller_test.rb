require "test_helper"
require "zip"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @tempfiles = []
  end

  teardown do
    @tempfiles.each do |file|
      file.close
      file.unlink
    end
  end

  test "index renders standalone contracts only for the selected tenant" do
    own_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    own_contract.update!(tenant: tenants(:one))
    foreign_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    foreign_contract.update!(tenant: tenants(:two))
    bundled_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    Bundle.create!(tenant: tenants(:one), contracts: [ bundled_contract ])
    user = users(:one)
    user.update_column(:confirmed_at, Time.current)
    sign_in user

    get contracts_path

    assert_response :success
    assert_equal user, request.env["warden"].user(:user)
    assert_select "a[href=?]", contract_path(own_contract), minimum: 1
    assert_select "a[href=?] .sr-only", contract_path(own_contract), text: ": #{own_contract.display_name}", count: 2
    assert_select "a[href=?][data-turbo-method='delete'][data-turbo-confirm=?]", contract_path(own_contract),
                  I18n.t("contracts.destroy.confirm", name: own_contract.display_name)
    assert_select "a[href=?]", contract_path(foreign_contract), count: 0
    assert_select "a[href=?]", contract_path(bundled_contract), count: 0
  end

  test "anonymous actions show disabled account features and authentication CTA" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])

    get actions_contract_path(contract)

    assert_response :success
    assert_select "input[type='radio'][disabled][value='request_signature']", count: 1
    assert_select "input[type='radio'][disabled][value='add_timestamp']", count: 1
    assert_select "input[type='radio'][disabled][value='archive_signature']", count: 1
    assert_select "form[action='#{authenticate_for_actions_contract_path(contract)}'][data-turbo-frame='_top']", count: 1
  end

  test "actions back link leaves the contract page" do
    anonymous_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    own_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    own_contract.update!(tenant: tenants(:one))
    bundled_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    bundle = Bundle.create!(tenant: tenants(:one), contracts: [ bundled_contract ])
    back = I18n.t("documents.new.actions.back")

    get contract_path(anonymous_contract)
    assert_select "a[href=?]", new_contract_path, text: back

    user = users(:one)
    user.update_column(:confirmed_at, Time.current)
    sign_in user

    get contract_path(own_contract)
    assert_equal user, request.env["warden"].user(:user)
    assert_select "a[href=?]", contracts_path, text: back

    get actions_contract_path(own_contract)
    assert_select "a[href=?]", contracts_path, text: back

    get contract_path(bundled_contract)
    assert_select "a[href=?]", bundle_path(bundle), text: back
    assert_select "a[href=?]", contract_path(bundled_contract), text: back, count: 0
  end

  test "anonymous contract can be viewed but deletion requires route authentication" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])

    get contract_path(contract)
    assert_response :success

    assert_no_difference -> { Contract.count } do
      delete contract_path(contract)
    end
    assert_redirected_to new_user_session_path
  end

  test "anonymous contract cannot request signatures" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])

    get signature_parameters_contract_path(contract, target_step: "request_signature")
    assert_response :forbidden

    assert_no_difference -> { Bundle.count } do
      patch contract_path(contract), params: { next_step: "request_signature" }
    end
    assert_response :forbidden
    assert_nil contract.reload.tenant
  end

  test "foreign tenant contract updates retain redirect without mutation" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    contract.update!(tenant: tenants(:two))
    users(:one).update_column(:confirmed_at, Time.current)
    sign_in users(:one)

    get contract_path(contract)
    assert_redirected_to new_contract_path
    assert_equal I18n.t("contracts.alerts.unauthorized_edit_attempt"), flash[:alert]

    patch contract_path(contract), params: { contract: { allowed_methods: [ "visual" ] } }
    assert_redirected_to new_contract_path
    assert_equal [ "qes" ], contract.reload.allowed_methods
  end

  test "contract of another own tenant keeps selected tenant guidance" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    contract.update!(tenant: tenants(:two))
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: users(:one))
    users(:one).update_column(:confirmed_at, Time.current)
    sign_in users(:one)
    post tenant_selection_path(tenant_id: tenants(:one).id)

    get contract_path(contract)

    assert_redirected_to dashboard_path
    assert_equal I18n.t("tenants.alerts.other_tenant_record", name: tenants(:two).name), flash[:alert]
    assert_equal tenants(:one).id, session[:current_tenant_id]
  end

  test "revoked membership cannot reuse a previously selected tenant" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    contract.update!(tenant: tenants(:one))
    users(:one).update_column(:confirmed_at, Time.current)
    sign_in users(:one)
    get contract_path(contract)
    assert_response :success

    Membership.where(user: users(:one)).delete_all

    assert_no_difference -> { Contract.count } do
      delete contract_path(contract)
    end
    assert_redirected_to tenant_selection_path
    assert Contract.exists?(contract.id)
  end

  test "authentication claims pending anonymous contract and returns to its actions" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    user = users(:one)
    user.update_columns(confirmed_at: Time.current)

    post authenticate_for_actions_contract_path(contract)
    assert_redirected_to new_user_session_path

    sign_in user
    get contract_path(contract)

    assert_response :success
    assert_equal user.tenants.sole, contract.reload.tenant
  end

  test "pending claim only applies to the selected contract" do
    pending_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    other_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    user = users(:one)
    user.update_columns(confirmed_at: Time.current)

    post authenticate_for_actions_contract_path(pending_contract)
    sign_in user

    get contract_path(other_contract)
    assert_nil other_contract.reload.tenant

    get contract_path(pending_contract)
    assert_equal user.tenants.sole, pending_contract.reload.tenant
  end

  test "owned and bundled contracts cannot enter anonymous claim flow" do
    owned_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    owned_contract.update!(tenant: tenants(:one))
    bundled_contract = create_pdf_contract(allowed_methods: [ "qes" ])
    Bundle.create!(tenant: tenants(:one), contracts: [ bundled_contract ])

    post authenticate_for_actions_contract_path(owned_contract)
    assert_response :forbidden

    post authenticate_for_actions_contract_path(bundled_contract)
    assert_response :forbidden

    get actions_contract_path(owned_contract)
    assert_response :success
    assert_select "form[action='#{authenticate_for_actions_contract_path(owned_contract)}']", count: 0

    get actions_contract_path(bundled_contract)
    assert_response :success
    assert_select "form[action='#{authenticate_for_actions_contract_path(bundled_contract)}']", count: 0
  end

  test "pending claim survives required policy consent" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    user = users(:two)
    user.update_columns(confirmed_at: Time.current)

    post authenticate_for_actions_contract_path(contract)
    sign_in user
    get actions_contract_path(contract)
    assert_redirected_to new_consent_path

    post consent_path, params: { agree_to_policies: "1" }
    assert_redirected_to contract_path(contract)

    follow_redirect!
    assert_equal user.tenants.sole, contract.reload.tenant
  end

  test "signature apps show incompatible qscd choices disabled without launch links" do
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])

    get signature_apps_contract_path(contract, qscd: "eid_2021")

    assert_response :success
    assert_equal %w[autogram podpisuj avm eidentita], signature_app_values
    assert_select "input[data-signing-app-selector-target='appRadio']", count: 4
    assert_select "input[data-signing-app-selector-target='appRadio'][disabled]", count: 2
    assert_select "input[value='avm'][disabled]", count: 1
    assert_select "input[value='eidentita'][disabled]", count: 1
    assert_select "label[tabindex], label[aria-disabled]", count: 0
    reason_id = css_select("input[value='avm'][disabled]").first["aria-describedby"]
    assert_select "[id='#{reason_id}']", text: /\S/, count: 1
    assert_select "a[data-signing-app-selector-target='autogramSubmitButton']", count: 1
    assert_select "a[data-signing-app-selector-target='podpisujSubmitButton']", count: 1
    assert_select "a[data-signing-app-selector-target='avmSubmitButton']", count: 0
    assert_select "a[data-signing-app-selector-target='eidentitaSubmitButton']", count: 0
    assert_includes response.body, I18n.t("contracts.signature_apps.unavailable_reasons.unsupported_qscd", qscd: I18n.t("qscd.title.eid_2021"))
  end

  test "embedded signature apps enable all compatible choices" do
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])

    get signature_apps_contract_path(contract, qscd: "eid_2024", embedded: true)

    assert_response :success
    assert_equal %w[autogram avm eidentita podpisuj], signature_app_values
    assert_select "input[data-signing-app-selector-target='appRadio']", count: 4
    assert_select "input[data-signing-app-selector-target='appRadio'][disabled]", count: 0
    assert_select "input[data-desktop-only='true']", count: 2
    assert_select "a[data-signing-app-selector-target$='SubmitButton']", count: 4
  end

  test "signature apps of a standalone contract show apps that cannot sign its level disabled" do
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])
    contract.signature_parameters.update!(level: "BASELINE_T")

    get signature_apps_contract_path(contract, qscd: "eid_2024")

    assert_response :success
    assert_select "input[value='podpisuj'][disabled]", count: 1
    assert_equal %w[autogram avm eidentita podpisuj], signature_app_values
    assert_includes response.body, I18n.t("contracts.signature_apps.unavailable_reasons.unsupported_signature_level")
  end

  test "signature apps leave out apps that cannot sign the requested format in an iframe" do
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])
    contract.signature_parameters.update!(level: "BASELINE_T")

    get signature_apps_contract_path(contract, qscd: "eid_2024", iframe: "true")

    assert_response :success
    assert_select "input[data-signing-app-selector-target='appRadio']", count: 3
    assert_select "input[value='podpisuj']", count: 0
    assert_not_includes response.body, I18n.t("contracts.signature_apps.unavailable_reasons.unsupported_signature_level")
  end

  test "signature apps of a bundled contract leave out apps that cannot sign its format but keep card restrictions" do
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])
    contract.signature_parameters.update!(level: "BASELINE_T")
    bundle = Bundle.create!(tenant: tenants(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "signer@example.com")

    get signature_apps_contract_path(contract, recipient: recipient.uuid, qscd: "eid_2021")

    assert_response :success
    assert_select "input[data-signing-app-selector-target='appRadio']", count: 3
    assert_select "input[value='podpisuj']", count: 0
    assert_select "input[value='autogram']:not([disabled])", count: 1
    assert_select "input[value='avm'][disabled]", count: 1
    assert_select "input[value='eidentita'][disabled]", count: 1
    assert_not_includes response.body, I18n.t("contracts.signature_apps.unavailable_reasons.unsupported_signature_level")
  end

  test "signature apps leave out standalone apps unless standalone signing is allowed" do
    contract = create_pdf_contract(allowed_methods: [ "qes" ])

    get signature_apps_contract_path(contract, qscd: "eid_2024")

    assert_response :success
    assert_equal %w[autogram avm eidentita], signature_app_values
    assert_select "a[data-signing-app-selector-target='podpisujSubmitButton']", count: 0
  end

  test "signature apps offer only standalone apps when qes is not allowed" do
    contract = create_pdf_contract(allowed_methods: [ "standalone_qes" ])

    get signature_apps_contract_path(contract, qscd: "eid_2024")

    assert_response :success
    assert_equal %w[podpisuj], signature_app_values
    assert_select "a[data-signing-app-selector-target='podpisujSubmitButton']", count: 1
  end

  test "uploaded own contract allows standalone apps by default and the author can turn them off" do
    post contracts_path, params: {
      document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 own"), "application/pdf", original_filename: "own.pdf") },
      contract: { agree_to_policies: "1" }
    }
    contract = Contract.order(:id).last
    assert_equal [ "qes", "standalone_qes" ], contract.allowed_methods

    get signature_parameters_contract_path(contract, target_step: "sign")
    assert_select "input[name='contract[allowed_methods][]'][value='standalone_qes'][checked]", count: 1

    put "/contracts/#{contract.uuid}", params: {
      next_step: "sign",
      contract: {
        allowed_methods: [ "qes" ],
        signature_parameters_attributes: { id: contract.signature_parameters.id, level: "BASELINE_B", format: "PAdES" }
      }
    }

    assert_redirected_to sign_contract_path(contract)
    assert_equal [ "qes" ], contract.reload.allowed_methods
  end

  test "requesting signatures leaves standalone apps unchecked by default" do
    user = users(:one)
    user.update_columns(confirmed_at: Time.current)
    contract = create_pdf_contract(allowed_methods: [ "qes", "standalone_qes" ])
    contract.update!(tenant: tenants(:one))
    sign_in user

    get signature_parameters_contract_path(contract, target_step: "request_signature")

    assert_response :success
    assert_select "input[name='contract[allowed_methods][]'][value='qes'][checked]", count: 1
    assert_select "input[name='contract[allowed_methods][]'][value='standalone_qes']", count: 1
    assert_select "input[name='contract[allowed_methods][]'][value='standalone_qes'][checked]", count: 0

    put "/contracts/#{contract.uuid}", params: {
      next_step: "request_signature",
      contract: { allowed_methods: [ "qes" ] }
    }

    assert_redirected_to contract.reload.bundle
    assert_equal [ "qes" ], contract.allowed_methods
  end

  test "visual signing creates stamped content and marks signer signed" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])
      stamp_service = fake_stamp_service("stamped visual pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: {
            page: 1,
            x: 120.5,
            y: 88.25,
            width: 200,
            height: 60,
            custom_text: "Placed stamp",
            content_mode: "text"
          }
        }
      end

      session = contract.reload.signer_contracts.last.sessions.order(:id).last
      assert_redirected_to contract_session_path(contract, session, show_completed: true)

      contract.reload
      signer_contract = contract.signer_contracts.last
      signer_contract.reload
      assert signer_contract.signed?
      assert_equal 1, contract.content_versions.count
      assert_equal "visual", contract.latest_content_version.origin
      assert_equal "stamped visual pdf", contract.latest_content_version.content

      visual_stamp = signer_contract.visual_stamps.visual_method.last
      assert_equal 120.5, visual_stamp.x.to_f
      assert_equal 88.25, visual_stamp.y.to_f
      assert_equal 200.0, visual_stamp.width.to_f
      assert_equal 60.0, visual_stamp.height.to_f
      assert_equal "Placed stamp", visual_stamp.text
      assert_equal({ page: 1, x: 120.5, y: 88.25, width: 200.0, height: 60.0, text: "Placed stamp" }, stamp_service.last_stamp)
      assert_equal "%PDF-1.4 test content", stamp_service.last_document_content
    end
  end

  test "additional visual signing builds on finalized visual document" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])
      stamp_service = fake_stamp_service("first stamped visual pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: { custom_text: "First", content_mode: "text" }
        }

        stamp_service.content = "second stamped visual pdf"
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: { custom_text: "Second", content_mode: "text" }
        }
      end

      contract.reload
      signer_contract = contract.signer_contracts.last
      assert_equal 2, signer_contract.visual_stamps.visual_method.count
      assert_equal "Second", signer_contract.visual_stamps.visual_method.last.text
      assert_equal 1, contract.content_versions.where(origin: "visual").count
      assert_equal "second stamped visual pdf", contract.latest_content_version.content
      assert_equal "first stamped visual pdf", stamp_service.last_document_content
    end
  end

  test "visual signing preview shows latest finalized visual document" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])

      with_autogram_service(fake_stamp_service("first stamped visual pdf")) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: { custom_text: "First", content_mode: "text" }
        }
      end

      get "/contracts/#{contract.uuid}/visual_signing"

      assert_response :success
      assert_includes response.body, rails_blob_path(contract.reload.latest_content_version.file, disposition: "inline")
      assert_not_includes response.body, rails_blob_path(contract.documents.first.blob, disposition: "inline")
    end
  end

  test "editing qes visual preparation replaces older stamp from original document" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pdf_contract(allowed_methods: [ "qes", "visual" ])
      stamp_service = fake_stamp_service("first prepared qes pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          purpose: "qes_preparation",
          stamp: { custom_text: "First", content_mode: "text" }
        }

        stamp_service.content = "second prepared qes pdf"
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          purpose: "qes_preparation",
          stamp: { custom_text: "Second", content_mode: "text" }
        }
      end

      contract.reload
      signer_contract = contract.signer_contracts.last
      assert_equal 1, signer_contract.visual_stamps.qes_preparation.count
      assert_equal "Second", signer_contract.visual_stamps.qes_preparation.last.custom_text
      assert_equal "second prepared qes pdf", signer_contract.visual_stamps.qes_preparation.last.file.download
      assert_equal "%PDF-1.4 test content", stamp_service.last_document_content
    end
  end

  test "qes visual preparation stores prepared source without marking signer signed" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pdf_contract(allowed_methods: [ "qes", "visual" ])
      stamp_service = fake_stamp_service("prepared qes pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          recipient: "",
          purpose: "qes_preparation",
          stamp: { custom_text: "Jane Doe", content_mode: "text" }
        }
      end

      assert_redirected_to signature_apps_contract_path(contract)

      signer_contract = contract.signer_contracts.last
      assert_not signer_contract.signed?
      assert_equal 0, contract.content_versions.count
      assert_equal 1, signer_contract.visual_stamps.qes_preparation.count
      assert_equal "prepared qes pdf", signer_contract.visual_stamps.qes_preparation.last.file.download
      assert_equal [ VisualStamp::QES_MANDATORY_TEXT, "Jane Doe" ].join("\n"), stamp_service.last_stamp[:text]
    end
  end

  test "prepared signature field redirects signing flow to locked appearance step" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field

    with_autogram_service(fake_unsigned_pades_validation_service) do
      get "/contracts/#{contract.uuid}/sign", params: { recipient: recipient.uuid }

      assert_redirected_to visual_signing_contract_path(contract, recipient: recipient.uuid, purpose: "signature_field_appearance")

      get "/contracts/#{contract.uuid}/signature_apps", params: { recipient: recipient.uuid }

      assert_redirected_to visual_signing_contract_path(contract, recipient: recipient.uuid, purpose: "signature_field_appearance")
    end
  end

  test "prepared signature field appearance stores editable content without stamping the pdf" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field

    with_autogram_service(fake_unsigned_pades_validation_service) do
      post "/contracts/#{contract.uuid}/visual_signing", params: {
        recipient: recipient.uuid,
        purpose: "signature_field_appearance",
        stamp: { custom_text: "Jane Visible", content_mode: "text" }
      }
    end

    assert_redirected_to signature_apps_contract_path(contract, recipient: recipient.uuid)

    signer_contract = recipient.recipient_signer.signer_contracts.find_by!(contract: contract)
    appearance = signer_contract.visual_stamps.signature_field_appearance.last
    assert_equal "Jane Visible", appearance.text
    assert_not appearance.file.attached?
    assert_equal 0, contract.reload.content_versions.where(origin: "visual").count
  end

  test "prepared signature field appearance resumes ades flow when requested" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field(allowed_methods: [ "ades" ], mobile_phone: "+421901234567")

    with_autogram_service(fake_unsigned_pades_validation_service) do
      post "/contracts/#{contract.uuid}/visual_signing", params: {
        recipient: recipient.uuid,
        purpose: "signature_field_appearance",
        resume_signing_method: "ades",
        stamp: { custom_text: "Jane Visible", content_mode: "text" }
      }
    end

    assert_redirected_to ades_contract_sessions_path(contract, recipient: recipient.uuid)
  end

  test "prepared signature field appearance with drawing stores image without text" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field

    with_autogram_service(fake_unsigned_pades_validation_service) do
      post "/contracts/#{contract.uuid}/visual_signing", params: {
        recipient: recipient.uuid,
        purpose: "signature_field_appearance",
        stamp: { content_mode: "draw", drawing_data: png_data_url }
      }
    end

    assert_redirected_to signature_apps_contract_path(contract, recipient: recipient.uuid)

    signer_contract = recipient.recipient_signer.signer_contracts.find_by!(contract: contract)
    appearance = signer_contract.visual_stamps.signature_field_appearance.last
    assert appearance.image.attached?
    assert_nil appearance.text
    assert_not appearance.file.attached?
  end

  test "prepared signature field request inside signature apps frame renders appearance prompt instead of missing content" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field

    with_autogram_service(fake_unsigned_pades_validation_service) do
      get "/contracts/#{contract.uuid}/signature_apps",
          params: { recipient: recipient.uuid, embedded: true },
          headers: { "Turbo-Frame" => "signature_apps_#{contract.uuid}" }
    end

    assert_response :success
    assert_includes response.body, "turbo-frame id=\"signature_apps_#{contract.uuid}\""
    assert_select "a[href='#{visual_signing_contract_path(contract, recipient: recipient.uuid, purpose: 'signature_field_appearance')}'][data-turbo-frame='_top']"
  end

  test "prepared signature field remains required for later recipient after another recipient signs" do
    contract, _first_recipient, second_recipient = create_bundle_contract_with_two_prepared_signature_fields
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed by first recipient",
      filename: "visual-test-signed-once.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    with_autogram_service(fake_unsigned_pades_validation_service) do
      get "/contracts/#{contract.uuid}/sign", params: { recipient: second_recipient.uuid }

      assert_redirected_to visual_signing_contract_path(contract, recipient: second_recipient.uuid, purpose: "signature_field_appearance")
    end
  end

  test "prepared signature field appearance remains available after another recipient signs pades" do
    contract, _first_recipient, second_recipient = create_bundle_contract_with_two_prepared_signature_fields
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed by first recipient",
      filename: "visual-test-signed-once.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )

    with_autogram_service(fake_pades_validation_service) do
      get "/contracts/#{contract.uuid}/visual_signing", params: {
        recipient: second_recipient.uuid,
        purpose: "signature_field_appearance"
      }

      assert_response :success
      assert_select "input[name='purpose'][value='signature_field_appearance']", count: 1
      assert_includes response.body, VisualStamp::PADES_VISUAL_SIGNATURE_BY_PREFIX
      assert_not_includes response.body, "border-amber-300"
    end
  end

  test "visual signing can use image instead of custom text" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])
      stamp_service = fake_stamp_service("image stamped visual pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: {
            content_mode: "image",
            image: png_upload
          }
        }
      end

      visual_stamp = contract.reload.signer_contracts.last.visual_stamps.visual_method.last
      assert visual_stamp.image.attached?
      assert_nil visual_stamp.text
      assert_equal "image/png", stamp_service.last_stamp[:imageMimeType]
      assert Base64.strict_decode64(stamp_service.last_stamp[:imageContent]).present?
    end
  end

  test "visual signing can use drawing data instead of uploaded image" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])
      stamp_service = fake_stamp_service("drawn visual pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: {
            content_mode: "draw",
            drawing_data: png_data_url
          }
        }
      end

      visual_stamp = contract.reload.signer_contracts.last.visual_stamps.visual_method.last
      assert visual_stamp.image.attached?
      assert_nil visual_stamp.text
      assert_equal "image/png", stamp_service.last_stamp[:imageMimeType]
      assert Base64.strict_decode64(stamp_service.last_stamp[:imageContent]).present?
    end
  end

  test "visual signing validation errors are shown only next to the form" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])

      with_autogram_service(fake_stamp_service("unused")) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: { page: 1, x: 40, y: 40, width: 200, height: 52, custom_text: "", content_mode: "text" }
        }
        assert_redirected_to visual_signing_contract_path(contract, purpose: "visual_method")

        follow_redirect!
      end

      assert_response :success
      assert_select "[role='alert']", count: 1
      assert_select "#visual_stamp_errors[role='alert']", count: 1
      assert_select "[aria-invalid='true'][aria-describedby~='visual_stamp_errors']", minimum: 1
      assert_not_includes response.body, "custom_text&quot;]"
      assert_not_includes response.body, "[&quot;"
    end
  end

  test "visual signing validation renders remembered visual signature" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])

      with_autogram_service(fake_stamp_service("visual validation pdf")) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: {
            custom_text: "Visible Name",
            content_mode: "text"
          }
        }
      end

      get "/contracts/#{contract.uuid}/validate"

      assert_response :success
      assert_includes response.body, I18n.t("shared.signature_validation.visual_signatures_found_title")
      assert_includes response.body, "Visible Name"
      assert_not_includes response.body, I18n.t("shared.signature_validation.no_signatures_title")
    end
  end

  test "visual signing is not available for already pades signed contract" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pades_signed_contract(allowed_methods: [ "qes", "visual" ])

      with_autogram_service(fake_pades_validation_service) do
        get "/contracts/#{contract.uuid}/sign"

        assert_response :success
        assert_select "a[data-signing-method-target='visualButton']", count: 0
        assert_select "a[href='#{visual_signing_contract_path(contract, purpose: 'qes_preparation')}']", count: 0

        get "/contracts/#{contract.uuid}/visual_signing"

        assert_redirected_to sign_contract_path(contract)
        assert_equal I18n.t("contracts.alerts.visual_signing_not_available_for_signed_pades"), flash[:alert]
      end
    end
  end

  test "creating visual signing is blocked for already pades signed contract" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pades_signed_contract(allowed_methods: [ "qes", "visual" ])

      with_autogram_service(fake_pades_validation_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: { custom_text: "Blocked", content_mode: "text" }
        }
      end

      assert_redirected_to sign_contract_path(contract)
      assert_equal I18n.t("contracts.alerts.visual_signing_not_available_for_signed_pades"), flash[:alert]
      assert_equal 1, contract.reload.content_versions.count
      assert_equal 0, contract.signer_contracts.flat_map(&:visual_stamps).count
    end
  end

  test "sign advanced settings sanitize visual method for pades on update leaves visual before any signature" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pdf_contract(allowed_methods: [ "qes", "visual" ])

      put "/contracts/#{contract.uuid}", params: {
        next_step: "sign",
        contract: {
          allowed_methods: [ "qes", "visual" ],
          signature_parameters_attributes: {
            id: contract.signature_parameters.id,
            level: "BASELINE_B",
            format: "PAdES"
          }
        }
      }

      assert_redirected_to sign_contract_path(contract)
      assert_equal [ "qes", "visual" ], contract.reload.allowed_methods
    end
  end

  test "show renders a visualization toggle per document for uploaded ASiC-E" do
    contract = Contract.new(
      documents: [ Document.new(blob: asice_blob("container.asice", {
        "contract-a.txt" => "alpha",
        "contract-b.txt" => "beta",
        "META-INF/signatures.xml" => "<signature/>"
      })) ]
    )
    assert contract.save, contract.errors.full_messages.to_sentence

    get "/contracts/#{contract.uuid}"

    assert_response :success
    assert_select "turbo-frame[id^='document_visualization_']", count: 2
    assert_select "iframe[data-src]", count: 0
  end

  test "show renders direct iframe for signed PDF source" do
    contract = create_pades_signed_contract(allowed_methods: [ "qes" ])

    get "/contracts/#{contract.uuid}"

    assert_response :success
    assert_select "iframe[data-src='#{rails_blob_path(contract.latest_source_content_version.file, disposition: 'inline')}#toolbar=0&navpanes=0&scrollbar=0&view=FitH']", count: 1
    assert_select "turbo-frame[id^='document_visualization_']", count: 0
  end

  private

  def signature_app_values
    css_select("input[data-signing-app-selector-target='appRadio']").map { |radio| radio["value"] }
  end

  def create_pdf_contract(allowed_methods:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "visual-test.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      allowed_methods: allowed_methods,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
  end

  def create_pades_signed_contract(allowed_methods:)
    contract = create_pdf_contract(allowed_methods: allowed_methods)
    contract.add_signed_content_version!(
      content: "%PDF-1.4 signed content",
      filename: "visual-test-signed.pdf",
      content_type: "application/pdf",
      origin: "signing"
    )
    contract
  end

  def asice_blob(filename, entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end

    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(buffer.string),
      filename: filename,
      content_type: "application/vnd.etsi.asic-e+zip"
    )
  end

  def create_bundle_contract_with_prepared_signature_field(allowed_methods: [ "qes" ], mobile_phone: nil)
    contract = create_pdf_contract(allowed_methods: allowed_methods)
    bundle = Bundle.create!(tenant: tenants(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en", mobile_phone: mobile_phone)

    with_autogram_service(fake_unsigned_pades_validation_service) do
      contract.signature_field_preparations.create!(
        recipient: recipient,
        document: contract.documents.first,
        page: 2,
        x: 42,
        y: 64,
        width: 180,
        height: 64
      )
    end

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "visual-test-prepared-fields.pdf",
      content_type: "application/pdf"
    )

    [ contract.reload, recipient.reload ]
  end

  def create_bundle_contract_with_two_prepared_signature_fields
    contract = create_pdf_contract(allowed_methods: [ "qes" ])
    bundle = Bundle.create!(tenant: tenants(:one), contracts: [ contract ])
    first_recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    second_recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")

    with_autogram_service(fake_unsigned_pades_validation_service) do
      [ first_recipient, second_recipient ].each_with_index do |recipient, index|
        contract.signature_field_preparations.create!(
          recipient: recipient,
          document: contract.documents.first,
          page: 1,
          x: 42 + (index * 120),
          y: 64,
          width: 180,
          height: 64
        )
      end
    end

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "visual-test-prepared-fields.pdf",
      content_type: "application/pdf"
    )

    [ contract.reload, first_recipient.reload, second_recipient.reload ]
  end

  def fake_stamp_service(content)
    Struct.new(:content, :last_stamp, :last_document_content) do
      def stamp_pdf(_document, stamp:)
        self.last_stamp = stamp
        self.last_document_content = _document.content
        content
      end
    end.new(content)
  end

  def fake_pades_validation_service
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(
      AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [],
        documentInfo: { signatureForm: "PAdES" }
      )
    )
  end

  def fake_unsigned_pades_validation_service
    Struct.new(:validation_result) do
      def validate_signatures(_document)
        validation_result
      end
    end.new(
      AutogramService::ValidationResult.new(
        hasSignatures: false,
        signatures: [],
        documentInfo: { signatureForm: "PAdES" }
      )
    )
  end

  def png_upload
    file = Tempfile.new([ "stamp", ".png" ])
    @tempfiles << file
    file.binmode
    file.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lwL9NwAAAABJRU5ErkJggg=="))
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  def png_data_url
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lwL9NwAAAABJRU5ErkJggg=="
  end

  def with_autogram_service(fake_service)
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_autogram_service, :autogram_service)
    environment_singleton.send(:define_method, :autogram_service) { fake_service }

    yield
  ensure
    environment_singleton.send(:remove_method, :autogram_service)
    environment_singleton.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment_singleton.send(:remove_method, :__original_autogram_service)
  end

  def with_allowed_methods(methods)
    original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, methods)

    yield
  ensure
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, original_allowed_methods)
  end
end
