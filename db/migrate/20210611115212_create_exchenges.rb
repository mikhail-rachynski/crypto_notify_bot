class CreateExchenges < ActiveRecord::Migration[5.2]
  def change
    create_table :exchenges do |t|
      t.integer :pair
      t.integer :value
      t.timestamps
    end
  end
end
