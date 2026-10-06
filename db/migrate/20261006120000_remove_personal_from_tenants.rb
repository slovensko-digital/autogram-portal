# The UI tells personal tenants apart by plan (Basic) instead.
class RemovePersonalFromTenants < ActiveRecord::Migration[8.1]
  def change
    remove_column :tenants, :personal, :boolean, null: false, default: false
  end
end
