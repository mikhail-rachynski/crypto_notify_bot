class CreateCoins < ActiveRecord::Migration[5.2]
  def change
    create_table :coins do |t|
      t.string :coin
      t.integer :currency
      t.integer :user_id
      t.timestamps
    end
  end
end
