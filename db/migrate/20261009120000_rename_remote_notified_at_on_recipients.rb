# Čas odoslania pozvánky sa zobrazuje pri lokálnych aj federovaných adresátoch.
class RenameRemoteNotifiedAtOnRecipients < ActiveRecord::Migration[8.0]
  def change
    rename_column :recipients, :remote_notified_at, :notified_at
  end
end
