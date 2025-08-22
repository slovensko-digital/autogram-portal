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

ActiveRecord::Schema[8.0].define(version: 2025_08_22_110435) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ades_signing_parameters", force: :cascade do |t|
    t.string "level"
    t.string "signature_form"
    t.string "signature_baseline_level"
    t.string "container"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "ades_xdc_properties", force: :cascade do |t|
    t.boolean "auto_load_eform"
    t.string "container_xmlns"
    t.boolean "embed_used_schemas"
    t.string "identifier"
    t.text "schema"
    t.string "schema_identifier"
    t.text "transformation"
    t.string "transformation_identifier"
    t.string "transformation_language"
    t.string "transformation_media_destination_type_description"
    t.string "transformation_target_environment"
    t.bigint "signing_parameter_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["signing_parameter_id"], name: "index_ades_xdc_properties_on_signing_parameter_id"
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

  create_table "documents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "uuid"
    t.bigint "bundle_id", null: false
    t.string "allowed_methods", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id"], name: "index_documents_on_bundle_id"
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

  create_table "signing_files", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "uuid"
    t.bigint "document_id", null: false
    t.string "url"
    t.string "remote_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_signing_files_on_document_id"
    t.index ["user_id"], name: "index_signing_files_on_user_id"
    t.index ["uuid"], name: "index_signing_files_on_uuid"
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

  add_foreign_key "ades_xdc_properties", "ades_signing_parameters", column: "signing_parameter_id"
  add_foreign_key "bundles", "users"
  add_foreign_key "bundles_recipients", "bundles"
  add_foreign_key "bundles_recipients", "users", column: "recipient_id"
  add_foreign_key "documents", "bundles"
  add_foreign_key "documents", "users"
  add_foreign_key "postal_addresses", "bundles"
  add_foreign_key "signing_files", "documents"
  add_foreign_key "signing_files", "users"
  add_foreign_key "webhooks", "bundles"
end
