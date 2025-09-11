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

ActiveRecord::Schema[8.0].define(version: 2025_08_22_112214) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ades_signature_parameters", force: :cascade do |t|
    t.string "level"
    t.string "signature_form"
    t.string "signature_baseline_level"
    t.string "container"
    t.boolean "add_content_timestamp"
    t.boolean "en319132"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "bundles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "uuid"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_bundles_on_user_id"
    t.index ["uuid"], name: "index_bundles_on_uuid"
  end

  create_table "bundles_recipients", id: false, force: :cascade do |t|
    t.bigint "bundle_id", null: false
    t.bigint "recipient_id", null: false
    t.index ["bundle_id", "recipient_id"], name: "index_bundles_recipients_on_bundle_id_and_recipient_id"
    t.index ["recipient_id", "bundle_id"], name: "index_bundles_recipients_on_recipient_id_and_bundle_id"
  end

  create_table "contracts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "uuid"
    t.bigint "bundle_id", null: false
    t.string "allowed_methods", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_contracts_on_bundle_id"
    t.index ["user_id"], name: "index_contracts_on_user_id"
    t.index ["uuid"], name: "index_contracts_on_uuid"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "uuid"
    t.bigint "contract_id"
    t.string "url"
    t.string "remote_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["contract_id"], name: "index_documents_on_contract_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
    t.index ["uuid"], name: "index_documents_on_uuid"
  end

  create_table "postal_addresses", force: :cascade do |t|
    t.text "address"
    t.string "recipient_name"
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_postal_addresses_on_bundle_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "api_token_public_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "webhooks", force: :cascade do |t|
    t.string "url"
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_webhooks_on_bundle_id"
  end

  create_table "xdc_parameters", force: :cascade do |t|
    t.string "fs_form_identifier"
    t.string "identifier"
    t.string "container_xmlns"
    t.boolean "embed_used_schemas"
    t.text "schema"
    t.string "schema_mime_type"
    t.string "schema_identifier"
    t.text "transformation"
    t.string "transformation_identifier"
    t.string "transformation_language"
    t.string "transformation_media_destination_type_description"
    t.string "transformation_target_environment"
    t.bigint "document_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_xdc_parameters_on_document_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bundles", "users"
  add_foreign_key "bundles_recipients", "bundles"
  add_foreign_key "bundles_recipients", "users", column: "recipient_id"
  add_foreign_key "contracts", "bundles"
  add_foreign_key "contracts", "users"
  add_foreign_key "documents", "contracts"
  add_foreign_key "documents", "users"
  add_foreign_key "postal_addresses", "bundles"
  add_foreign_key "webhooks", "bundles"
  add_foreign_key "xdc_parameters", "documents"
end
