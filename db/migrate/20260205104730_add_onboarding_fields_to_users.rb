class AddOnboardingFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :completed_onboardings, :jsonb, default: [], null: false
    add_column :users, :eid_card_generation, :integer
  end
end
