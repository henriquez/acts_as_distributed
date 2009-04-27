ActiveRecord::Schema.define(:version => 3) do

  create_table "distributes", :force => true do |t|
    t.string   "distributed_id",   :limit => 36,     :null => false
    t.string   "distributed_type"
    t.string   "client_id"
    t.string   "action"
    t.string    "changes"
    t.boolean  "error", :default => false
    t.string   "messages", :default => ""
    t.datetime "processed_at"
    t.datetime "created_at"
  end

 create_table :users, :force => true do |t|
    t.column :uuid, :string, :limit => 36
    t.column :name, :string
    t.column :username, :string
    t.column :password, :string
    t.column :activated, :boolean
    t.column :logins, :integer, :default => 0
    t.column :created_at, :datetime
    t.column :updated_at, :datetime
  end
  
  create_table :products, :force => true do |t|
     t.column :uuid, :string, :limit => 36
     t.column :name, :string
     t.column :features, :string
     t.column :created_at, :datetime
     t.column :updated_at, :datetime
   end

end
