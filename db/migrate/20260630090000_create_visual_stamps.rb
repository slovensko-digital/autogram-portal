class CreateVisualStamps < ActiveRecord::Migration[8.1]
  def change
    create_table :visual_stamps do |t|
      t.references :signer_contract, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.string :purpose, null: false
      t.integer :page, null: false, default: 1
      t.decimal :x, precision: 10, scale: 2, null: false
      t.decimal :y, precision: 10, scale: 2, null: false
      t.decimal :width, precision: 10, scale: 2, null: false
      t.decimal :height, precision: 10, scale: 2, null: false
      t.text :text

      t.timestamps
    end

    add_index :visual_stamps, [ :signer_contract_id, :document_id, :purpose ]
  end
end
