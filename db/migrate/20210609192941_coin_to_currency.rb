class CoinToCurrency < ActiveRecord::Migration[5.2]
  def change
    create_table :coins_to_currencies, id: false do |t|
      t.integer :coin_id
      t.integer :to_currency_id
      t.timestamps
    end
  end
end
