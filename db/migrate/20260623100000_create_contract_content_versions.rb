class CreateContractContentVersions < ActiveRecord::Migration[8.1]
  class MigrationAttachment < ApplicationRecord
    self.table_name = "active_storage_attachments"
  end

  def up
    create_table :contract_content_versions do |t|
      t.references :contract, null: false, foreign_key: true
      t.integer :version_number, null: false
      t.string :origin, null: false, default: "signed"

      t.timestamps
    end

    add_index :contract_content_versions, [ :contract_id, :version_number ], unique: true

    say_with_time "Reassigning existing signed contract attachments to contract content versions" do
      MigrationAttachment.where(record_type: "Contract", name: "signed_document").find_each do |attachment|
        created_at = attachment.created_at || Time.current
        version_id = insert_contract_content_version(attachment.record_id, created_at)

        attachment.update!(record_type: "ContractContentVersion", record_id: version_id, name: "file")
      end
    end
  end

  def down
    say_with_time "Reassigning contract content versions back to contract signed_document attachments" do
      MigrationAttachment.where(record_type: "ContractContentVersion", name: "file").find_each do |attachment|
        version = select_value(<<~SQL.squish)
          SELECT contract_id
          FROM contract_content_versions
          WHERE id = #{attachment.record_id.to_i}
        SQL

        next if version.blank?

        attachment.update!(record_type: "Contract", record_id: version.to_i, name: "signed_document")
      end
    end

    drop_table :contract_content_versions
  end

  private

  def insert_contract_content_version(contract_id, created_at)
    execute(<<~SQL.squish)
      INSERT INTO contract_content_versions (contract_id, version_number, origin, created_at, updated_at)
      VALUES (#{contract_id.to_i}, 1, 'legacy_signed_document', #{quote(created_at)}, #{quote(created_at)})
    SQL

    select_value(<<~SQL.squish)
      SELECT id
      FROM contract_content_versions
      WHERE contract_id = #{contract_id.to_i}
      ORDER BY id DESC
      LIMIT 1
    SQL
  end
end
