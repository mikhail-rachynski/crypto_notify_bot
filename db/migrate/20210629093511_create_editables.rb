class CreateEditables < ActiveRecord::Migration[5.2]
  def change
    create_table :editables do |t|
      t.integer :user_id
      t.boolean :status
      t.timestamps
    end
  end
end
