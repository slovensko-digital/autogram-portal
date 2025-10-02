class CreateSignatureParameters < ActiveRecord::Migration[8.0]
  def change
    create_table :ades_signature_parameters do |t|
      t.string :level
      t.string :format
      t.string :container
      t.boolean :add_content_timestamp
      t.boolean :en319132
      t.belongs_to :contract, null: false, foreign_key: true

      t.timestamps
    end
  end
end
