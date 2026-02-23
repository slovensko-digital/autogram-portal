class AddOnboardingFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :completed_onboardings, :jsonb, default: [], null: false
    add_column :users, :qscd, :integer
  end
end
