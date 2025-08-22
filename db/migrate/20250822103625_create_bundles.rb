class CreateBundles < ActiveRecord::Migration[8.0]
  def change
    create_table :bundles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :uuid

      t.timestamps
    end
    add_index :bundles, :uuid
  end
end
