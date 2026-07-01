class CreateSignatureFieldPreparations < ActiveRecord::Migration[8.1]
  def change
    create_table :signature_field_preparations do |t|
      t.references :contract, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.references :recipient, null: false, foreign_key: true
      t.string :field_identifier, null: false
      t.integer :page, null: false, default: 1
      t.decimal :x, precision: 10, scale: 2, null: false
      t.decimal :y, precision: 10, scale: 2, null: false
      t.decimal :width, precision: 10, scale: 2, null: false
      t.decimal :height, precision: 10, scale: 2, null: false

      t.timestamps
    end

    add_index :signature_field_preparations, :field_identifier, unique: true
    add_index :signature_field_preparations,
              [ :recipient_id, :contract_id, :document_id ],
              unique: true,
              name: "idx_signature_fields_on_recipient_contract_document"
  end
end
