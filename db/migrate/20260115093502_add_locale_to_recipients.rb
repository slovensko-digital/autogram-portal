class AddLocaleToRecipients < ActiveRecord::Migration[8.1]
  def change
    add_column :recipients, :locale, :string, null: false, default: "sk"
  end
end
