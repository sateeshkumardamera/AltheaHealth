class AddSrToUsers < ActiveRecord::Migration
  def change
  	add_column :users, :sr, :string
  end
end
