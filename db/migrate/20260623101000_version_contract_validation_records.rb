class VersionContractValidationRecords < ActiveRecord::Migration[8.1]
  def up
    add_reference :contract_validation_records, :contract_content_version, null: true, foreign_key: { on_delete: :nullify }
    add_column :contract_validation_records, :source_version_number, :integer

    backfill_version_columns

    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_and_contract_uuid"
    change_column_null :contract_validation_records, :source_version_number, false
    add_index :contract_validation_records,
              [ :user_id, :source_contract_uuid, :source_version_number ],
              unique: true,
              name: "index_contract_validation_records_on_user_contract_and_version"
  end

  def down
    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_contract_and_version"
    add_index :contract_validation_records,
              [ :user_id, :source_contract_uuid ],
              unique: true,
              name: "index_contract_validation_records_on_user_and_contract_uuid"
    remove_reference :contract_validation_records, :contract_content_version, foreign_key: true
    remove_column :contract_validation_records, :source_version_number
  end

  private

  def backfill_version_columns
    execute <<~SQL.squish
      UPDATE contract_validation_records records
      SET contract_content_version_id = versions.id,
          source_version_number = versions.version_number
      FROM contract_content_versions versions
      WHERE versions.contract_id = records.contract_id
        AND records.contract_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE contract_validation_records
      SET source_version_number = COALESCE(source_version_number, 1)
      WHERE source_version_number IS NULL
    SQL
  end
end
