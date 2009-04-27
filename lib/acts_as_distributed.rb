# Copyright (c) 2006 Brandon Keepers
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=begin

NOTES FOR USAGE IN FRONTEND
The event gets recorded in a db table called Distribute, and works using 
callbacks like after_create, after_update, and after_destroy.  
Generally your code in the frontend doesn't need to be aware of this process.  
The one caveat is that when a user deletes a source (or any other 
model like UserSubscription, etc), you must use object.destroy not 
Class.delete(uuid), since the latter does not trigger a callback and 
also does not clean up associations.

NOTES FOR USAGE WITH BACKEND
You can expect the following in the distributes row:
  distributed_id  = the uuid of the object the action took place on
  changes = a hash of changes to the object, i.e.
    if create - all the attributes in the object saved to the db
    if update - only the attributes that changed, not the whole object.
    if destroy - all the attributes that were in the object now deleted
  action = the action performed on the object, one of 'update', 'create', or 'destroy'

The messages col is now generically used for inter-process messages as well 
as intra-process (ie between iterations) messaging. Put strings into the messages column
by doing this in the object's model file (no db entry required)
  attr_accessor :messages_for_distribution
  
and then assign it a value before the object is saved. Acts_as_distributed will take
whatever is in messages_for_distribution and put it in the 'messages' column of the event
to be interpreted by the receivers.

See the readme in this plugin for conventions on messages.  
=end

module Core #:nodoc:
  module Acts #:nodoc:
    # Specify this act if you want changes to your model to be saved in an
    # distribute table.  This assumes there is an distributes table ready.
    #
    #   class User < ActiveRecord::Base
    #     acts_as_distributed
    #   end
    #
    # See <tt>CollectiveIdea::Acts::distributed::ClassMethods#acts_as_distributed</tt>
    # for configuration options
    module Distributed #:nodoc:
      CALLBACKS = [:distribute_create, :distribute_update, :distribute_destroy]

      def self.included(base) # :nodoc:
        base.extend ClassMethods
      end

      module ClassMethods
        # == Configuration options
        #
        # * <tt>except</tt> - Excludes fields from being saved in the distribute log.
        #   By default, acts_as_distributeed will distribute all but these fields: 
        # 
        #     [self.primary_key, inheritance_column,  'created_at', 'updated_at']
        #
        #   You can add to those by passing one or an array of fields to skip.
        #
        #     class User < ActiveRecord::Base
        #       acts_as_distributed :except => :password
        #     end
        # 
        def acts_as_distributed(options = {})
          # don't allow multiple calls
          return if self.included_modules.include?(Core::Acts::Distributed::InstanceMethods)

          include Core::Acts::Distributed::InstanceMethods
          
          class_inheritable_reader :non_distributed_columns
          class_inheritable_reader :distribute_enabled

          except = [self.primary_key, inheritance_column, 'created_at', 'updated_at', 'id']
          except |= [options[:except]].flatten.collect(&:to_s) if options[:except]
          write_inheritable_attribute :non_distributed_columns, except

          class_eval do
            extend Core::Acts::Distributed::SingletonMethods
            # note the use of 'distributed' drives the need  for 'distributed_id' and 
            # 'distributed_type' in the distributes table definition - polymorphic association. 
            # :distributes is the name of the table where changes are stored.     
            # distributed_id is the uuid of the object that is being distributed (i.e. updated, saved, or deleted) 
            # as long as that object has set_primary_key 'uuid'    
            # this has_many is primarily for testing purposes, not used elsewhere.  
            has_many :distributes, :as => :distributed 
            
            after_create :distribute_create
            after_update :distribute_update
            
            # must be before_destroy not after because need to fill the changes hash with the object's
            # contents for use by UserSubscriptions to id the user_uuid and group_uuid that is
            # impacted by the destroy.  This could be changed back to after if not on a shared database
            # and the UserSubscriptions handles news updates before it destroys its local object
            # TODO: change this so its configurable somewhere to be or not to be on a shared db.
            before_destroy :distribute_destroy

            write_inheritable_attribute :distribute_enabled, true
          end
        end
      end
    
      module InstanceMethods
        
        def changed_distributed_attributes
          attributes.slice(*changed_attributes.keys).except(*non_distributed_columns)
        end

        # Returns the attributes that are distributed
        def distributed_attributes
          attributes.except(*non_distributed_columns)
        end
        
        # Temporarily turns off distributing while saving.
        def save_without_distributing
          without_distributing { save }
        end
        

        # Executes the block with the distributing callbacks disabled.
        #
        #   @foo.without_distributing do
        #     @foo.save
        #   end
        #
        def without_distributing(&block)
          self.class.without_distributing(&block)
        end
        
        

      private
      
        
        # Creates a new record in the distributes table. Note that messages_for_distribution
        # may not be defined by the class being distributed if the class has no need to pass
        # messages, so we just write nothing if that's the case.   
        def distribute_create
          # note rescue must return "" not nil or will screw distribute's find
          vals = "#{messages_for_distribution} " rescue ""
          self.distributes.create :action => 'create', 
                                  :changes => distributed_attributes, 
                                  :messages => vals
        end

        # remember that self is instance of class whose changes are being saved to distributes table
        def distribute_update
          # note rescue must return "" not nil or will screw distribute's find
          vals = "#{messages_for_distribution} " rescue ""
          unless (changes = changed_distributed_attributes).empty?
            self.distributes.create :action => 'update', 
                                    :changes => changes, 
                                    :messages => vals
          end
        end
        
        # self is an instance of the class whose changes are being saved to the distributes table.
        # If on same db, b1 tier needs to have the attributes of the destroyed object for
        # UserSubscriptions to recreate the right news instances.
        def distribute_destroy
          self.distributes.create :action => 'destroy', :changes => distributed_attributes
        end
        
 

        CALLBACKS.each do |attr_name| 
          alias_method "orig_#{attr_name}".to_sym, attr_name
        end
        
        def empty_callback() end #:nodoc:

      end # InstanceMethods
      
      module SingletonMethods
        # Returns an array of columns that are distributed.  See non_distributed_columns
        def distributed_columns
          self.columns.select { |c| !non_distributed_columns.include?(c.name) }
        end

        # Executes the block with the distributing callbacks disabled.
        #
        #   Foo.without_distributing do
        #     @foo.save
        #   end
        #
        def without_distributing(&block)
          distributing_was_enabled = distribute_enabled
          disable_distributing
          returning(block.call) { enable_distributing if distributing_was_enabled }
        end
        
        def disable_distributing
          class_eval do 
            CALLBACKS.each do |attr_name| 
              alias_method attr_name, :empty_callback
            end
          end
          write_inheritable_attribute :distribute_enabled, false
        end
        
        def enable_distributing
          class_eval do 
            CALLBACKS.each do |attr_name|
              alias_method attr_name, "orig_#{attr_name}".to_sym
            end
          end
          write_inheritable_attribute :distribute_enabled, true
        end

      end
    end
  end
end
