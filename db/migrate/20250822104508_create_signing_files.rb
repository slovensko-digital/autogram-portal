class CreateSigningFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :signing_files do |t|
      t.references :user, null: false, foreign_key: true
      t.string :uuid
      t.references :document, null: false, foreign_key: true
      t.string :url
      t.string :remote_hash

      t.timestamps
    end
    add_index :signing_files, :uuid
  end
end
