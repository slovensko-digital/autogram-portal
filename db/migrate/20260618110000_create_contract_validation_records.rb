class CreateContractValidationRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :contract_validation_records do |t|
      t.references :user, null: false, foreign_key: true
      t.references :contract, null: true, foreign_key: { on_delete: :nullify }

      t.string :source_contract_uuid, null: false
      t.string :source_bundle_uuid
      t.string :filename, null: false
      t.string :document_hash, null: false
      t.string :signature_levels, array: true, default: [], null: false
      t.integer :signatures_count, null: false, default: 0
      t.datetime :expires_at
      t.datetime :latest_archive_timestamp_expires_at
      t.jsonb :validation_details, null: false, default: {}

      t.timestamps
    end

    add_index :contract_validation_records,
              [ :user_id, :source_contract_uuid ],
              unique: true,
              name: "index_contract_validation_records_on_user_and_contract_uuid"
    add_index :contract_validation_records, [ :user_id, :expires_at ]
    add_index :contract_validation_records, :document_hash
  end
end