class CreateSigningParameters < ActiveRecord::Migration[8.0]
  def change
    create_table :ades_signing_parameters do |t|
      t.string :level
      t.string :signature_form
      t.string :signature_baseline_level
      t.string :container

      t.timestamps
    end
  end
end
