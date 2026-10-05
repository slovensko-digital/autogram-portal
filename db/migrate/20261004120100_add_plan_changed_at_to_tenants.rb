# Retention of the new plan applies only after a grace period since the plan changed,
# e.g. documents of a cancelled PRO plan are kept for a while before Basic retention deletes them.
class AddPlanChangedAtToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :plan_changed_at, :datetime
  end
end
