# Usage of a tenant that counts towards its monthly plan limits and is the basis for billing.
# Records outlive the contracts they were made for, so deleting a bundle never resets the count.
class CreateUsageRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_records do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.references :contract, foreign_key: { on_delete: :nullify }, index: false
      t.string :kind, null: false
      t.string :source, null: false
      t.integer :quantity, null: false, default: 1
      t.datetime :created_at, null: false
    end

    add_index :usage_records, [ :tenant_id, :kind, :created_at ]
    # A document sent for signature is counted only once.
    add_index :usage_records, :contract_id, unique: true, where: "kind = 'signature_request'",
              name: "index_usage_records_on_signature_request_contract"
    add_index :usage_records, :contract_id
  end
end
