require File.dirname(__FILE__) + '/test_helper'

class DistributeTest < ActiveSupport::TestCase

  
  def test_get_one_valid_create_event
    Distribute.delete_all
    user = User.create! :name => 'happy talker'
    assert_equal 'happy talker', Distribute.get_new_row(:all).changes['name']   
    assert_equal 'happy talker', Distribute.get_new_row(:all).changes['name'] # idempotent       
  end
  
  # Should read multiple records in, returning the first one.  The rest should be in 
  # the row_cache.  There should be no errored rows.
  def test_get_and_delete_multiple_rows
    Distribute.delete_all
    user = User.create! :name => 'happy talker'
    user = User.create! :name => 'back talker' 
    user = User.create! :name => 'nasty talker'         
    row1 =  Distribute.get_new_row(:all)       
    assert_equal 'happy talker', row1.changes['name']
    # should continue to return the same row until its deleted for this process.
    assert_equal 'happy talker', Distribute.get_new_row(:all).changes['name']
    row1.destroy
    # now that event is deleted should get next event
    assert_equal 'back talker', Distribute.get_new_row(:all).changes['name']
  end
  
  
  # if distributed_type == 'Source' the row should be handled by both source_updater and 
  # event processor, so handling is different than other classes.
  def test_get_source_events
    Distribute.delete_all
    o1 = Distribute.create(:distributed_id => 'a', :distributed_type => 'Source', :messages => "",
                       :action => 'create', :changes => {'whatever' => 'value1'} , :error => false )
    o2 = Distribute.create(:distributed_id => 'b', :distributed_type => 'Source', :messages => "",
                      :action => 'destroy', :changes => {'whatever' => 'value1'} , :error => false )                   
    assert_equal 'a', Distribute.get_new_row(:all).distributed_id              
    # rows that have the string 'event' in the messages attribs should not be returned if arg == :all
    # because this indicates that event processor has already handled the event
    o1.update_attribute('messages', "event ")
    assert_equal 'b', Distribute.get_new_row(:all).distributed_id   
    # requests with :source argument should continue to return events until messages has the 
    # 'source' string in it.       
    assert_equal 'a', Distribute.get_new_row(:source).distributed_id
    # conversely if source_updater has handled the event, it should still be returned for event processor
    o1.update_attribute('messages', "source ")
    assert_equal 'a', Distribute.get_new_row(:all).distributed_id
  end
  
  # source rows require that the event has been processed already by event_processor
  def test_get_only_source_rows  
    Distribute.delete_all
    # get source rows only 
    Distribute.create(:distributed_id => 'a uuid', :distributed_type => 'Source', 
                      :messages => 'event ',
                      :action => 'create', :changes => 'whatever' )  
    assert_equal 'a uuid', Distribute.get_new_row(:source).distributed_id                   
  end
  
  # get_new_row should not return errored events, get_errored_row should
  def test_getting_errored_rows
    Distribute.delete_all
    user = User.create! :name => 'error'
    row = Distribute.find(:all).first
    row.error = true
    row.save!
    assert_nil Distribute.get_new_row(:all)
    assert Distribute.get_errored_row(:all).changes['name'] == 'error'
  end
  

  def test_record_errored_event
    Distribute.delete_all
    user = User.create! :name => 'error' 
    row = Distribute.get_new_row(:all)
    row.record_error
    # the errored event should have the error flag set 
    errored_event = Distribute.find(:first)
    assert_equal true, errored_event.error
  end
  
  
  def test_errored_events_dont_block_valid_events
    Distribute.delete_all
    user = User.create! :name => 'error' # this one shouldn't block the others
    errored_row = Distribute.find(:first)
    errored_row.record_error
    user = User.create! :name => 'happy' 
    user = User.create! :name => 'dopey' 
    # get_new_row should only get non-errored events even if they occured after the errored event
    assert_equal 'happy',  Distribute.get_new_row(:all).changes['name']
  end
  
  
  def test_get_randomized_errored_event
    Distribute.delete_all
    o1 = Distribute.create(:distributed_id => 'a uuid', :distributed_type => 'Source', 
                      :action => 'create', :changes => 'whatever', :error => true,
                      :messages => "event ", :processed_at => 1.hour.ago)
    o2 = Distribute.create(:distributed_id => 'another uuid', :distributed_type => 'Source', 
                      :action => 'create', :changes => 'whatever', :error => true,
                      :messages => "event ", :processed_at => 1.hour.ago )
    o3 = Distribute.create(:distributed_id => 'a different uuid', :distributed_type => 'Source', 
                      :action => 'create', :changes => 'whatever', :error => true ,
                      :messages => "event ", :processed_at => 1.hour.ago)         
    it1 = Distribute.get_errored_row(:source) 
    it2 = Distribute.get_errored_row(:source)    
    it3 = Distribute.get_errored_row(:source)    
    it4 = Distribute.get_errored_row(:source)  
    # all the return values should not be the same(could be at low probl..)
    assert ![it1, it2, it3, it4].all? {|it| it.distributed_id == 'a uuid'} 
    o2.destroy
    o3.destroy
    # only one errored event now so should return it every time
    it1 = Distribute.get_errored_row(:source)   
    it2 = Distribute.get_errored_row(:source)    
    it3 = Distribute.get_errored_row(:source)    
    it4 = Distribute.get_errored_row(:source)  
    # all the return values should not be the same(could be at low probl..)
    assert [it1, it2, it3, it4].all? {|it| it.distributed_id == 'a uuid'}                                        
  end
  
  # like regular events, errored event get_errored_row should only return events
  # that have not been processed yet.
  def test_dont_get_errors_already_processed
    Distribute.delete_all
    o1 = Distribute.create(:distributed_id => 'a uuid', :distributed_type => 'Source', 
                      :action => 'create', :changes => 'whatever', :error => true,
                      :messages => "source ", :processed_at => 1.hour.ago)
    # the above event has been processed by source updater already, so should yield nil
    assert_nil Distribute.get_errored_row(:source)    
    Distribute.delete_all
    o1 = Distribute.create(:distributed_id => 'a uuid', :distributed_type => 'Source', 
                      :action => 'create', :changes => 'whatever', :error => true,
                      :messages => "event ", :processed_at => 1.hour.ago)
    # the above event has been processed by source updater already, so should yield nil
    assert_nil Distribute.get_errored_row(:all)               
  end
  
end





 