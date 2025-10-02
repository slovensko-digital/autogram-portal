class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.references :user, null: true, foreign_key: true
      t.string :uuid
      t.references :contract, null: true, foreign_key: true
      t.string :url
      t.string :remote_hash

      t.timestamps
    end
    add_index :documents, :uuid
  end
end
