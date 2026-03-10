class CreateSigners < ActiveRecord::Migration[8.1]
  def change
    create_table :signers do |t|
      t.string :type, null: false
      t.references :user, null: true, foreign_key: true
      t.references :recipient, null: true, foreign_key: true
      t.timestamps
    end
  end
end
