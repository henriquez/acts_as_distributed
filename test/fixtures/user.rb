
class User < ActiveRecord::Base
 
  acts_as_distributed :except => :username
  
  def self.current_user
  end
end