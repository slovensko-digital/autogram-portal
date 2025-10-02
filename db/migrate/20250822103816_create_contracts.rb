class CreateContracts < ActiveRecord::Migration[8.0]
  def change
    create_table :contracts do |t|
      t.references :user, null: true, foreign_key: true
      t.string :uuid
      t.references :bundle, null: true, foreign_key: true
      t.string :allowed_methods, array: true, default: []

      t.timestamps
    end
    add_index :contracts, :uuid
  end
end
