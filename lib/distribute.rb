######### USAGE #############
# 
# This class is used to pull events out of a database for consumption by other processes.  
# Accessed via the Event class.
######### DEPENDENCIES ############
# The Event model and the utilities plugin
###################################

########## Ideas to generalize  #######
=begin
1. get_new_row and get_errored_row must be able to search for events with any set of values in the messages column - not just event
   and source.  Retain the :all type, but it should capture the idea that :all means all distribute_types are 
   wanted, not the implementation today where it means more than that.
2. create an :after => [] argument to the two methods above do determine whether messages must have a value or values before
   it will be processed
3. Pass in  newest_errored_event_time as a paramter to Event - perhaps at the Event handler initialization.
4. change name from distributes.rb to something that illustrates what it does, like message 'consumer'    

=end

# Distribute saves the changes to ActiveRecord models.  It has the following attributes:
#
# * <tt>distributed_class</tt>: the ActiveRecord model (Class name) that was changed - camelcased
# * <tt>action</tt>: one of create, update, or destroy (note that we don't 
#                    record rails delete actions because they have no callbacks)
# * <tt>changes</tt>: a YAML serialized hash of all the changes to the object - for creates this is all the
#                     attribs that have been saved, for updates its only the changes, for destroy its
#                     all the attribs that were in the destroyed object.
# *     messages   : a string that is either null, or contains the strings "event" and/or "source"
#                     depending on which b1 tier process has handled the event. Currently the R2 process
#                     also uses it to indicated when UserSubscriptions events are part of a batch - they enter
#                     the string "batch"
# * <tt>created_at</tt>: Time that the change was performed

class Distribute < ActiveRecord::Base
  
  #### this portion required for acts_as_distributed to work 
  set_primary_key 'id'  # not sure why this is needed, but for some reason gets set to 'uuid' by default
  belongs_to :distributed, :polymorphic => true 
  serialize :changes
  #### end of required section
  
  #####
  ##### the following is an example of some of the things you could do when polling and using events
  ##### its expected that you'll replace this with application specific code, or if you have time
  ##### on your hands, TODO: generalize it and send me a pull request :-)
  #####
  
  ROWS_READ_PER_OPERATION = 3
      

  ######## instance methods #######
  
  
  def record_error
    self.update_attributes({:error => true, :processed_at => Time.now.utc }) 
  end
  
  
  ######### class methods ###########
  
  class <<  self 
   
    
    # Reads in 1 new (== not errored) rows from db and returns it.  if there's nothing to get, return nil.
    # The type argument is a symbol - either :all or :source to indicate which to handle.
    def get_new_row(type)
      # small limit to what we'll process because each could tie up the db for a time
      # and we don't want to do that when sharing a db. Don't look at events that this process
      # has already handled or are errored.  If type is :source, i.e. source_updater, then 
      # it should not process events until after event_processor has finished with it.
      # Change this when not on a shared db.
      cond_arr = type == :all ? ['error = ? AND messages NOT LIKE "%event%" ', false] : \
                                ['error = ? AND distributed_type = ? ' +
                                  'AND messages NOT LIKE "%source%" AND messages LIKE "%event%"', \
                                  false, 'Source']
      Distribute.find(:first, :conditions => cond_arr, :order => 'created_at') 
    rescue Exception  
      log_it :error, "Encountered error: #{$!} processing rows in distributes table, leaving event in table"  
      # leave update in distributes table otherwise event will be lost - allow retry after issue fixed.
      # flag event as errored so it doesn't block processing of good events
    end
     
    
    # returns one errored event or nil.  If there are more than one errored event, pick one at random.
    # Only get errored rows that have not been processed in the last 30 minutes, to prevent tight
    # looping on a small number of errored events that were just looked at.
    def get_errored_row(type)
      cond_arr = type == :all ? ['error = ? AND messages NOT LIKE "%event%" AND (processed_at < ? OR processed_at IS NULL)', true, Distribute.newest_errored_event_time] : \
                                ['error = ? AND distributed_type = ? AND ' + 
                                  'messages NOT LIKE "%source%" AND messages LIKE "%event%" AND ' +
                                  '(processed_at < ? OR processed_at IS NULL)', true, 'Source', Distribute.newest_errored_event_time]

      # if many errored events, pick one at random.
      count = Distribute.count(:conditions => cond_arr)
      if count > 1
        offset = rand(count)
        row = Distribute.find(:first, :conditions => cond_arr, :offset => offset) 
      elsif count == 1
        row = Distribute.find(:first, :conditions => cond_arr)   
      else  # count == 0
        row = nil
      end
      row    
    rescue Exception  
        log_it :error, "Encountered error: #{$!} processing rows in distributes table, leaving event in table"  
        # leave update in distributes table otherwise event will be lost - allow retry after issue fixed.
        # flag event as errored so it doesn't block processing of good events  
    end
    
    
    
    # Used to determine which events to reprocess
    def newest_errored_event_time
       30.minutes.ago.utc 
    end

  end  # end class methods

end