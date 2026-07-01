# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_01_143000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ades_signature_parameters", force: :cascade do |t|
    t.boolean "add_content_timestamp"
    t.string "container"
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.boolean "en319132"
    t.string "format"
    t.string "level"
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_ades_signature_parameters_on_contract_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.boolean "author_notifications_enabled", default: false, null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.boolean "publicly_visible", default: false, null: false
    t.integer "required_signatures"
    t.string "signing_rule", default: "all", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index ["user_id"], name: "index_bundles_on_user_id"
    t.index ["uuid"], name: "index_bundles_on_uuid"
  end

  create_table "contract_content_versions", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.string "origin", default: "signed", null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["contract_id", "version_number"], name: "idx_on_contract_id_version_number_0129589952", unique: true
    t.index ["contract_id"], name: "index_contract_content_versions_on_contract_id"
  end

  create_table "contract_validation_records", force: :cascade do |t|
    t.bigint "contract_content_version_id"
    t.bigint "contract_id"
    t.datetime "created_at", null: false
    t.string "document_hash", null: false
    t.datetime "expires_at"
    t.string "filename", null: false
    t.datetime "latest_archive_timestamp_expires_at"
    t.string "signature_levels", default: [], null: false, array: true
    t.integer "signatures_count", default: 0, null: false
    t.string "source_bundle_uuid"
    t.string "source_contract_uuid", null: false
    t.integer "source_version_number", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "validation_details", default: {}, null: false
    t.index ["contract_content_version_id"], name: "idx_on_contract_content_version_id_7e3d0b9366"
    t.index ["contract_id"], name: "index_contract_validation_records_on_contract_id"
    t.index ["document_hash"], name: "index_contract_validation_records_on_document_hash"
    t.index ["user_id", "expires_at"], name: "index_contract_validation_records_on_user_id_and_expires_at"
    t.index ["user_id", "source_contract_uuid", "source_version_number"], name: "index_contract_validation_records_on_user_contract_and_version", unique: true
    t.index ["user_id"], name: "index_contract_validation_records_on_user_id"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "allowed_methods", default: [], array: true
    t.boolean "author_notifications_enabled", default: false, null: false
    t.bigint "bundle_id"
    t.datetime "created_at", null: false
    t.string "temporary_storage_reason"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "uuid", null: false
    t.index ["bundle_id"], name: "index_contracts_on_bundle_id"
    t.index ["temporary_storage_reason"], name: "index_contracts_on_temporary_storage_reason"
    t.index ["user_id"], name: "index_contracts_on_user_id"
    t.index ["uuid"], name: "index_contracts_on_uuid"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "contract_id"
    t.datetime "created_at", null: false
    t.string "remote_hash"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "uuid", null: false
    t.index ["contract_id"], name: "index_documents_on_contract_id"
    t.index ["uuid"], name: "index_documents_on_uuid"
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "callback_priority"
    t.text "callback_queue_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "discarded_at"
    t.datetime "enqueued_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
    t.text "on_discard"
    t.text "on_finish"
    t.text "on_success"
    t.jsonb "serialized_properties"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id", null: false
    t.datetime "created_at", null: false
    t.interval "duration"
    t.text "error"
    t.text "error_backtrace", array: true
    t.integer "error_event", limit: 2
    t.datetime "finished_at"
    t.text "job_class"
    t.uuid "process_id"
    t.text "queue_name"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_type", limit: 2
    t.jsonb "state"
    t.datetime "updated_at", null: false
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "key"
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "active_job_id"
    t.uuid "batch_callback_id"
    t.uuid "batch_id"
    t.text "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "cron_at"
    t.text "cron_key"
    t.text "error"
    t.integer "error_event", limit: 2
    t.integer "executions_count"
    t.datetime "finished_at"
    t.boolean "is_discrete"
    t.text "job_class"
    t.text "labels", array: true
    t.datetime "locked_at"
    t.uuid "locked_by_id"
    t.datetime "performed_at"
    t.integer "priority"
    t.text "queue_name"
    t.uuid "retried_good_job_id"
    t.datetime "scheduled_at"
    t.jsonb "serialized_params"
    t.datetime "updated_at", null: false
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at", where: "((retried_good_job_id IS NULL) AND (finished_at IS NOT NULL))"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id", "provider"], name: "index_identities_on_user_id_and_provider", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "portal_instances", force: :cascade do |t|
    t.string "allowed_email_domains", default: [], null: false, array: true
    t.string "base_url", null: false
    t.jsonb "capabilities", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "issuer", null: false
    t.datetime "last_verified_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "outbound_kid"
    t.text "public_key_pem", null: false
    t.string "status", default: "verified", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", null: false
    t.index ["issuer"], name: "index_portal_instances_on_issuer", unique: true
    t.index ["status"], name: "index_portal_instances_on_status"
    t.index ["uuid"], name: "index_portal_instances_on_uuid", unique: true
  end

  create_table "postal_addresses", force: :cascade do |t|
    t.text "address"
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.string "recipient_name"
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_postal_addresses_on_bundle_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "recipient_access_grants", force: :cascade do |t|
    t.string "claim_jti", null: false
    t.string "claimed_by_email", null: false
    t.string "claimed_by_external_user_id"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "portal_instance_id", null: false
    t.bigint "recipient_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", null: false
    t.index ["claim_jti"], name: "index_recipient_access_grants_on_claim_jti"
    t.index ["expires_at"], name: "index_recipient_access_grants_on_expires_at"
    t.index ["portal_instance_id"], name: "index_recipient_access_grants_on_portal_instance_id"
    t.index ["recipient_id"], name: "index_recipient_access_grants_on_recipient_id"
    t.index ["token_digest"], name: "index_recipient_access_grants_on_token_digest", unique: true
    t.index ["uuid"], name: "index_recipient_access_grants_on_uuid", unique: true
  end

  create_table "recipient_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_recipient_blocks_on_email", unique: true
  end

  create_table "recipients", force: :cascade do |t|
    t.boolean "author_proxy", default: false, null: false
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "federation_mode", default: "local", null: false
    t.string "locale", default: "sk", null: false
    t.string "mobile_phone"
    t.string "name"
    t.integer "notification_status", default: 0, null: false
    t.bigint "portal_instance_id"
    t.datetime "remote_claimed_at"
    t.string "remote_claimed_by_email"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "withdrawn_at"
    t.index ["bundle_id", "author_proxy", "withdrawn_at"], name: "idx_on_bundle_id_author_proxy_withdrawn_at_dd4336f6ca"
    t.index ["bundle_id", "email"], name: "index_recipients_on_bundle_id_and_email_active", unique: true, where: "(withdrawn_at IS NULL)"
    t.index ["bundle_id", "withdrawn_at"], name: "index_recipients_on_bundle_id_and_withdrawn_at"
    t.index ["bundle_id"], name: "index_recipients_on_bundle_id"
    t.index ["email"], name: "index_recipients_on_email"
    t.index ["federation_mode"], name: "index_recipients_on_federation_mode"
    t.index ["portal_instance_id"], name: "index_recipients_on_portal_instance_id"
    t.index ["user_id"], name: "index_recipients_on_user_id"
    t.index ["uuid"], name: "index_recipients_on_uuid", unique: true
    t.check_constraint "federation_mode::text = 'local'::text AND portal_instance_id IS NULL OR federation_mode::text = 'federated'::text AND portal_instance_id IS NOT NULL", name: "recipients_federation_mode_matches_portal_instance"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.jsonb "options", default: {}
    t.bigint "signer_contract_id", null: false
    t.datetime "signing_started_at"
    t.integer "status", default: 0, null: false
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["signer_contract_id"], name: "index_sessions_on_signer_contract_id"
    t.index ["type"], name: "index_sessions_on_type"
  end

  create_table "signature_evidence_records", force: :cascade do |t|
    t.jsonb "canonical_payload", default: {}, null: false
    t.bigint "contract_content_version_id"
    t.datetime "created_at", null: false
    t.datetime "locked_at"
    t.string "manifest_sha256"
    t.string "payload_sha256"
    t.string "public_reference", null: false
    t.bigint "session_id", null: false
    t.text "signed_manifest"
    t.bigint "signer_contract_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["contract_content_version_id"], name: "idx_on_contract_content_version_id_e898efe78b"
    t.index ["public_reference"], name: "index_signature_evidence_records_on_public_reference", unique: true
    t.index ["session_id"], name: "index_signature_evidence_records_on_session_id"
    t.index ["signer_contract_id"], name: "index_signature_evidence_records_on_signer_contract_id"
    t.index ["state"], name: "index_signature_evidence_records_on_state"
    t.index ["uuid"], name: "index_signature_evidence_records_on_uuid", unique: true
  end

  create_table "signature_field_preparations", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "field_identifier", null: false
    t.decimal "height", precision: 10, scale: 2, null: false
    t.integer "page", default: 1, null: false
    t.bigint "recipient_id", null: false
    t.datetime "updated_at", null: false
    t.decimal "width", precision: 10, scale: 2, null: false
    t.decimal "x", precision: 10, scale: 2, null: false
    t.decimal "y", precision: 10, scale: 2, null: false
    t.index ["contract_id"], name: "index_signature_field_preparations_on_contract_id"
    t.index ["document_id"], name: "index_signature_field_preparations_on_document_id"
    t.index ["field_identifier"], name: "index_signature_field_preparations_on_field_identifier", unique: true
    t.index ["recipient_id", "contract_id", "document_id"], name: "idx_signature_fields_on_recipient_contract_document", unique: true
    t.index ["recipient_id"], name: "index_signature_field_preparations_on_recipient_id"
  end

  create_table "signature_verifications", force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "channel", null: false
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.string "destination_digest", null: false
    t.datetime "expires_at"
    t.string "last_request_ip"
    t.string "last_user_agent"
    t.string "provider_request_id"
    t.datetime "sent_at"
    t.bigint "session_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["expires_at"], name: "index_signature_verifications_on_expires_at"
    t.index ["session_id"], name: "index_signature_verifications_on_session_id"
    t.index ["state"], name: "index_signature_verifications_on_state"
  end

  create_table "signer_contracts", force: :cascade do |t|
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.datetime "declined_at"
    t.datetime "signed_at"
    t.bigint "signer_id"
    t.datetime "superseded_at"
    t.datetime "updated_at", null: false
    t.index ["contract_id", "signed_at", "declined_at"], name: "index_signer_contracts_on_contract_and_signing_state"
    t.index ["contract_id"], name: "index_signer_contracts_on_contract_id"
    t.index ["declined_at"], name: "index_signer_contracts_on_declined_at_not_null", where: "(declined_at IS NOT NULL)"
    t.index ["signer_id", "contract_id"], name: "index_signer_contracts_on_signer_id_and_contract_id", unique: true
    t.index ["signer_id"], name: "index_signer_contracts_on_signer_id"
    t.index ["superseded_at"], name: "index_signer_contracts_on_superseded_at_not_null", where: "(superseded_at IS NOT NULL)"
  end

  create_table "signers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "recipient_id"
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["recipient_id"], name: "index_signers_on_recipient_id"
    t.index ["recipient_id"], name: "index_signers_on_recipient_id_unique_for_recipient_signers", unique: true, where: "(((type)::text = 'RecipientSigner'::text) AND (recipient_id IS NOT NULL))"
    t.index ["user_id"], name: "index_signers_on_user_id"
  end

  create_table "user_policy_consents", force: :cascade do |t|
    t.datetime "accepted_at", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.string "policy_type", null: false
    t.string "policy_version", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id", "accepted_at"], name: "index_user_policy_consents_on_user_id_and_accepted_at"
    t.index ["user_id", "policy_type", "policy_version"], name: "index_user_policy_consents_on_user_policy_version"
    t.index ["user_id"], name: "index_user_policy_consents_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token_public_key"
    t.jsonb "completed_onboardings", default: [], null: false
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.text "features", default: [], array: true
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "sk"
    t.datetime "locked_at"
    t.string "name"
    t.integer "qscd"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "visual_stamps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.decimal "height", precision: 10, scale: 2, null: false
    t.integer "page", default: 1, null: false
    t.string "purpose", null: false
    t.bigint "signer_contract_id", null: false
    t.text "text"
    t.datetime "updated_at", null: false
    t.decimal "width", precision: 10, scale: 2, null: false
    t.decimal "x", precision: 10, scale: 2, null: false
    t.decimal "y", precision: 10, scale: 2, null: false
    t.index ["document_id"], name: "index_visual_stamps_on_document_id"
    t.index ["signer_contract_id", "document_id", "purpose"], name: "idx_on_signer_contract_id_document_id_purpose_d86ba1c031"
    t.index ["signer_contract_id"], name: "index_visual_stamps_on_signer_contract_id"
  end

  create_table "webhooks", force: :cascade do |t|
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.integer "method", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["bundle_id"], name: "index_webhooks_on_bundle_id"
  end

  create_table "xdc_parameters", force: :cascade do |t|
    t.boolean "auto_load_eform"
    t.string "container_xmlns"
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.boolean "embed_used_schemas"
    t.string "fs_form_identifier"
    t.string "identifier"
    t.text "schema"
    t.string "schema_identifier"
    t.string "schema_mime_type"
    t.text "transformation"
    t.string "transformation_identifier"
    t.string "transformation_language"
    t.string "transformation_media_destination_type_description"
    t.string "transformation_target_environment"
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_xdc_parameters_on_document_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ades_signature_parameters", "contracts"
  add_foreign_key "bundles", "users"
  add_foreign_key "contract_content_versions", "contracts"
  add_foreign_key "contract_validation_records", "contract_content_versions", on_delete: :nullify
  add_foreign_key "contract_validation_records", "contracts", on_delete: :nullify
  add_foreign_key "contract_validation_records", "users"
  add_foreign_key "contracts", "bundles"
  add_foreign_key "contracts", "users"
  add_foreign_key "documents", "contracts"
  add_foreign_key "identities", "users"
  add_foreign_key "postal_addresses", "bundles"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "recipient_access_grants", "portal_instances"
  add_foreign_key "recipient_access_grants", "recipients"
  add_foreign_key "recipients", "bundles"
  add_foreign_key "recipients", "portal_instances"
  add_foreign_key "recipients", "users"
  add_foreign_key "sessions", "signer_contracts"
  add_foreign_key "signature_evidence_records", "contract_content_versions"
  add_foreign_key "signature_evidence_records", "sessions"
  add_foreign_key "signature_evidence_records", "signer_contracts"
  add_foreign_key "signature_field_preparations", "contracts"
  add_foreign_key "signature_field_preparations", "documents"
  add_foreign_key "signature_field_preparations", "recipients"
  add_foreign_key "signature_verifications", "sessions"
  add_foreign_key "signer_contracts", "contracts"
  add_foreign_key "signer_contracts", "signers"
  add_foreign_key "signers", "recipients"
  add_foreign_key "signers", "users"
  add_foreign_key "user_policy_consents", "users"
  add_foreign_key "visual_stamps", "documents"
  add_foreign_key "visual_stamps", "signer_contracts"
  add_foreign_key "webhooks", "bundles"
  add_foreign_key "xdc_parameters", "documents"
end
