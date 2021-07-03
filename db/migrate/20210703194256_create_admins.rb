class CreateAdmins < ActiveRecord::Migration[5.2]
  def change
    create_table :admins do |t|
      t.integer :user_id
      t.boolean :is_admin
      t.timestamps
    end
  end
end
