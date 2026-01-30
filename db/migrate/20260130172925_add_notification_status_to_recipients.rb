class AddNotificationStatusToRecipients < ActiveRecord::Migration[8.1]
  def up
    add_column :recipients, :notification_status, :integer, default: 0, null: false

    # Migrate existing recipients from status to notification_status
    execute <<-SQL
      UPDATE recipients
      SET notification_status = CASE
        WHEN status = 0 THEN 0  -- pending -> notifiable
        WHEN status = 1 THEN 2  -- notified -> notified
        WHEN status = 4 THEN 1  -- sending -> sending
        ELSE 0                  -- other statuses -> notifiable
      END
    SQL

    # Remove obsolete statuses from status enum
    execute <<-SQL
      UPDATE recipients
      SET status = CASE
        WHEN status = 0 THEN 0  -- pending -> pending
        WHEN status = 3 THEN 3  -- declined -> declined
        ELSE 0                  -- other statuses -> pending
      END
    SQL
  end

  def down
    remove_column :recipients, :notification_status
  end
end
