class CreateToCurrencies < ActiveRecord::Migration[5.2]
  def change
    create_table :to_currencies, id: false do |t|
      t.integer :currency
      t.timestamps
    end
  end
end
