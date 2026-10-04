# Signing in standalone apps (Podpisuj) used to be offered with every QES
# contract. It is now a separate allowed method, so existing contracts keep it.
class AllowStandaloneSigningForExistingContracts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE contracts
      SET allowed_methods = array_append(allowed_methods, 'standalone_qes')
      WHERE 'qes' = ANY(allowed_methods) AND NOT 'standalone_qes' = ANY(allowed_methods)
    SQL
  end

  def down
    execute <<~SQL
      UPDATE contracts
      SET allowed_methods = array_remove(allowed_methods, 'standalone_qes')
      WHERE 'standalone_qes' = ANY(allowed_methods)
    SQL
  end
end
