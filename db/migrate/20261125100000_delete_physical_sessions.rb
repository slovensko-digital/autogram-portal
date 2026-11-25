class DeletePhysicalSessions < ActiveRecord::Migration[8.1]
  def up
    execute "DELETE FROM sessions WHERE type = 'PhysicalSession'"
  end

  def down
    # irreversible: the deleted sessions cannot be restored
  end
end
