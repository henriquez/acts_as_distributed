

# this class is used to test for classes that defined messages_for_distribution and use them to put a 
# message into the event.
class Product < ActiveRecord::Base
  
  acts_as_distributed 
  attr_accessor :messages_for_distribution
  
  
end