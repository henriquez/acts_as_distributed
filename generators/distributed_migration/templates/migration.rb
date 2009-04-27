class <%= class_name %> < ActiveRecord::Migration
  def self.up
    create_table :distributes, :force => true do |t|
      t.integer :distributed_id   # this and next are for polymorphic association.
      t.string :distributed_type  # model name of the class being distributed
      t.string :client_id         # client where the action originated - for service side debugging
      t.string :action            # HTTP action
      t.text   :changes           # serialized list of the attributes that are sent in the update
      t.string :sent              # serialized list of services that received updates - used on if partial set received, NULL if none
      t.datetime :created_at
    end
  end

  def self.down
    drop_table :distributes
  end
end
