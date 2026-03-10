class MoveDeclineStateToSignerContracts < ActiveRecord::Migration[8.1]
  def up
    add_column :signer_contracts, :declined_at, :datetime

    execute <<~SQL
      UPDATE signer_contracts sc
      SET declined_at = COALESCE(sc.declined_at, sc.updated_at, NOW())
      FROM signers s, recipients r, contracts c
      WHERE sc.signer_id = s.id
        AND r.id = s.recipient_id
        AND c.id = sc.contract_id
        AND s.type = 'RecipientSigner'
        AND r.status = 3
        AND c.bundle_id = r.bundle_id
        AND sc.signed_at IS NULL
        AND sc.declined_at IS NULL
    SQL

    add_index :signer_contracts, [ :contract_id, :signed_at, :declined_at ], name: "index_signer_contracts_on_contract_and_signing_state"
    add_index :signer_contracts, :declined_at, where: "declined_at IS NOT NULL", name: "index_signer_contracts_on_declined_at_not_null"

    remove_index :recipients, :status
    remove_column :recipients, :status, :integer
  end

  def down
    add_column :recipients, :status, :integer, default: 0, null: false
    add_index :recipients, :status

    execute <<~SQL
      UPDATE recipients r
      SET status = 3
      WHERE EXISTS (
        SELECT 1
        FROM signers s
        JOIN signer_contracts sc ON sc.signer_id = s.id
        JOIN contracts c ON c.id = sc.contract_id
        WHERE s.type = 'RecipientSigner'
          AND s.recipient_id = r.id
          AND c.bundle_id = r.bundle_id
          AND sc.declined_at IS NOT NULL
      )
    SQL

    remove_index :signer_contracts, name: "index_signer_contracts_on_contract_and_signing_state"
    remove_index :signer_contracts, name: "index_signer_contracts_on_declined_at_not_null"

    remove_column :signer_contracts, :declined_at, :datetime
  end
end
