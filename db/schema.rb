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

ActiveRecord::Schema[8.1].define(version: 2026_01_20_133317) do
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

  create_table "avm_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.string "document_id"
    t.string "encryption_key"
    t.text "error_message"
    t.datetime "signing_started_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_avm_sessions_on_contract_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "uuid", null: false
    t.index ["user_id"], name: "index_bundles_on_user_id"
    t.index ["uuid"], name: "index_bundles_on_uuid"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "allowed_methods", default: [], array: true
    t.bigint "bundle_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "uuid", null: false
    t.index ["bundle_id"], name: "index_contracts_on_bundle_id"
    t.index ["user_id"], name: "index_contracts_on_user_id"
    t.index ["uuid"], name: "index_contracts_on_uuid"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "contract_id"
    t.datetime "created_at", null: false
    t.string "remote_hash"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id"
    t.string "uuid", null: false
    t.index ["contract_id"], name: "index_documents_on_contract_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
    t.index ["uuid"], name: "index_documents_on_uuid"
  end

  create_table "eidentita_sessions", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "contract_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "signing_started_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_eidentita_sessions_on_contract_id"
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

  create_table "postal_addresses", force: :cascade do |t|
    t.text "address"
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.string "recipient_name"
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_postal_addresses_on_bundle_id"
  end

  create_table "recipient_blocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_recipient_blocks_on_email", unique: true
  end

  create_table "recipients", force: :cascade do |t|
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "locale", default: "sk", null: false
    t.string "name"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["bundle_id", "email"], name: "index_recipients_on_bundle_id_and_email", unique: true
    t.index ["bundle_id"], name: "index_recipients_on_bundle_id"
    t.index ["email"], name: "index_recipients_on_email"
    t.index ["status"], name: "index_recipients_on_status"
    t.index ["user_id"], name: "index_recipients_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token_public_key"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "locale", default: "sk"
    t.datetime "locked_at"
    t.string "name"
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
  add_foreign_key "avm_sessions", "contracts"
  add_foreign_key "bundles", "users"
  add_foreign_key "contracts", "bundles"
  add_foreign_key "contracts", "users"
  add_foreign_key "documents", "contracts"
  add_foreign_key "documents", "users"
  add_foreign_key "eidentita_sessions", "contracts"
  add_foreign_key "identities", "users"
  add_foreign_key "postal_addresses", "bundles"
  add_foreign_key "recipients", "bundles"
  add_foreign_key "recipients", "users"
  add_foreign_key "webhooks", "bundles"
  add_foreign_key "xdc_parameters", "documents"
end
