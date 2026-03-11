class AddSigningRuleToBundlesAndSupersededAtToSignerContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :signing_rule, :string, null: false, default: "all"
    add_column :bundles, :required_signatures, :integer, null: true

    add_column :signer_contracts, :superseded_at, :datetime, null: true
    add_index :signer_contracts, :superseded_at,
              name: "index_signer_contracts_on_superseded_at_not_null",
              where: "superseded_at IS NOT NULL"
  end
end
