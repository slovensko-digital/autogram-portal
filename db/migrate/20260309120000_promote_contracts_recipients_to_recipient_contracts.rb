class PromoteContractsRecipientsToRecipientContracts < ActiveRecord::Migration[8.1]
  def up
    create_table :recipient_contracts do |t|
      t.references :recipient, null: false, foreign_key: true
      t.references :contract,  null: false, foreign_key: true
      t.datetime :signed_at
      t.timestamps
    end

    add_index :recipient_contracts, [ :recipient_id, :contract_id ], unique: true

    execute <<~SQL
      INSERT INTO recipient_contracts (recipient_id, contract_id, created_at, updated_at)
      SELECT recipient_id, contract_id, NOW(), NOW()
      FROM contracts_recipients
    SQL

    drop_table :contracts_recipients
  end

  def down
    create_table :contracts_recipients, id: false do |t|
      t.bigint :contract_id,  null: false
      t.bigint :recipient_id, null: false
    end

    add_index :contracts_recipients, [ :contract_id, :recipient_id ], unique: true
    add_foreign_key :contracts_recipients, :contracts
    add_foreign_key :contracts_recipients, :recipients

    execute <<~SQL
      INSERT INTO contracts_recipients (contract_id, recipient_id)
      SELECT contract_id, recipient_id FROM recipient_contracts
    SQL

    drop_table :recipient_contracts
  end
end
