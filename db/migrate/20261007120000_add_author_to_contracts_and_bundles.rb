class AddAuthorToContractsAndBundles < ActiveRecord::Migration[8.0]
  def change
    add_reference :contracts, :author, foreign_key: { to_table: :users, on_delete: :nullify }
    add_reference :bundles, :author, foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
