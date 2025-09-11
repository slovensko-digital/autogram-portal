class CreateSignatureParameters < ActiveRecord::Migration[8.0]
  def change
    create_table :ades_signature_parameters do |t|
      t.string :level
      t.string :signature_form
      t.string :signature_baseline_level
      t.string :container
      t.boolean :add_content_timestamp
      t.boolean :en319132

      t.timestamps
    end
  end
end
