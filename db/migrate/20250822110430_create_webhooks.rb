class CreateWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks do |t|
      t.string :url
      t.references :bundle, null: false, foreign_key: true

      t.timestamps
    end
  end
end
