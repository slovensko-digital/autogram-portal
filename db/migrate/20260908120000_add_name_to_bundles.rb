class AddNameToBundles < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :name, :string
  end
end