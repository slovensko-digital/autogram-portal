class BackfillContractValidationRecords < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    say_with_time "Backfilling contract validation records for signed and pre-signed contracts" do
      Contract.find_each do |contract|
        begin
          contract.send(:capture_existing_signed_content!)
        rescue StandardError => e
          Rails.logger.warn("Contract validation record backfill skipped for contract #{contract.id}: #{e.class}: #{e.message}")
        end
      end
    end
  end

  def down
  end
end
