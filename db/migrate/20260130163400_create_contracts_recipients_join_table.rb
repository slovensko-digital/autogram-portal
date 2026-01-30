class CreateContractsRecipientsJoinTable < ActiveRecord::Migration[8.1]
  def change
    create_table :contracts_recipients, id: false do |t|
      t.references :contract, null: false, foreign_key: true, index: true
      t.references :recipient, null: false, foreign_key: true, index: true
    end

    add_index :contracts_recipients, [ :contract_id, :recipient_id ], unique: true
  end
end
