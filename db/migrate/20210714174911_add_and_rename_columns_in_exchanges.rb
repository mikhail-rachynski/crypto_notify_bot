class AddAndRenameColumnsInExchanges < ActiveRecord::Migration[5.2]
  def change
    add_column :exchanges, :coin_id, :integer
    add_column :exchanges, :deviation, :float
    remove_column :exchanges, :pair, :integer
    add_column :coins, :to_currency, :integer
  end
end
