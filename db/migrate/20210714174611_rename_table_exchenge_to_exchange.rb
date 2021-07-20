class RenameTableExchengeToExchange < ActiveRecord::Migration[5.2]
  def change
    rename_table :exchenges, :exchanges
  end
end
