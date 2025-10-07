class EnsureAllRecordsHaveUuids < ActiveRecord::Migration[8.0]
  def up
    # Add UUIDs to any existing records that don't have them

    # Update contracts without UUIDs
    Contract.where(uuid: [nil, ""]).find_each do |contract|
      contract.update_column(:uuid, SecureRandom.uuid)
    end

    # Update bundles without UUIDs
    Bundle.where(uuid: [nil, ""]).find_each do |bundle|
      bundle.update_column(:uuid, SecureRandom.uuid)
    end

    # Update documents without UUIDs
    Document.where(uuid: [nil, ""]).find_each do |document|
      document.update_column(:uuid, SecureRandom.uuid)
    end

    # Add NOT NULL constraints to ensure UUIDs are always present
    change_column_null :contracts, :uuid, false
    change_column_null :bundles, :uuid, false
    change_column_null :documents, :uuid, false
  end

  def down
    # Remove NOT NULL constraints
    change_column_null :contracts, :uuid, true
    change_column_null :bundles, :uuid, true
    change_column_null :documents, :uuid, true
  end
end
