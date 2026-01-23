class AddFeaturesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :features, :text, array: true, default: []
  end
end
