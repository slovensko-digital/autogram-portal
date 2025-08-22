class CreateXdcProperties < ActiveRecord::Migration[8.0]
  def change
    create_table :ades_xdc_properties do |t|
      t.boolean :auto_load_eform
      t.string :container_xmlns
      t.boolean :embed_used_schemas
      t.string :identifier
      t.text :schema
      t.string :schema_identifier
      t.text :transformation
      t.string :transformation_identifier
      t.string :transformation_language
      t.string :transformation_media_destination_type_description
      t.string :transformation_target_environment
      t.references :signing_parameter, null: false, foreign_key: { to_table: :ades_signing_parameters }

      t.timestamps
    end
  end
end
