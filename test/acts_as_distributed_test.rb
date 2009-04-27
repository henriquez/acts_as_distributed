require File.join(File.dirname(__FILE__), 'test_helper')
# note these tests depend on the definition of the users table
# created in the schema.rb file in this plugin directory.
class ActsAsDistributedTest < Test::Unit::TestCase
  
  def test_acts_as_distributed_declaration
    [:non_distributed_columns, :distributed_columns, :without_distributing].each do |m|
      assert User.respond_to?(m), "User class should respond to #{m}."
    end

    u = User.new
    [:distributes, :save_without_distributing, :without_distributing, :distributed_attributes, :changed?].each do |m|
      assert u.respond_to?(m), "User object should respond to #{m}."
    end
  end
  
  # this has to be set according to the attributes in the user table as defined in the schema.rb 
  # file in this plugin' directory. 'name' is explicityly excluded in user.rb under fixtures 
  # so name should also be excluded in addition to the standard exclusions in non_distributed_columns  
  def test_distributed_attributes
    assert_equal [["activated", nil], ["logins", 0], ["name", nil], ["uuid", nil], ["password", nil]].sort, User.new.distributed_attributes.sort
  end
  
  def test_non_distributed_columns
    ['created_at', 'updated_at', 'username'].each do |column|
      assert User.non_distributed_columns.include?(column), "non_distributed_columns should include #{column}."
    end
  end

  def test_doesnt_save_non_distributed_columns
    u = create_user
    assert !u.distributes.first.changes.include?('created_at'), 'created_at should not be distributed'
    assert !u.distributes.first.changes.include?('updated_at'), 'updated_at should not be distributed'
    assert !u.distributes.first.changes.include?('username'), 'username should not be distributed'
    assert !u.distributes.first.changes.include?('id'), 'id should not be distributed'
  end
  
  def test_create_update_distribute
    u = nil
    # create
    assert_difference('Distribute.count', 1)    { u = create_user }
    assert_equal [['name', 'Brandon'], ['activated', nil], ['logins', 0], ['password', 'password'], ["uuid", nil]].sort, \
          Distribute.find(:all).last.changes.sort 
    # update
    assert_difference('Distribute.count', 1)    { assert u.update_attribute(:name, "Someone") }
    assert_equal "Someone", Distribute.find(:all).last.changes['name']
    # username is excepted from distribution in the user.rb in the testcase fixture.
    assert_no_difference('Distribute.count')    { assert u.update_attribute(:username, "mrxyz")    }
    # no change make so the below shouldn't save a distribute record
    assert_no_difference('Distribute.count') { assert u.save }
    # change made to excepted attribute and other attribute should still result in a save to distribute table
    # of the whole record.  excepted attributes are never saved, even in this scenario
    assert_difference('Distribute.count')  { assert u.update_attributes({:username => "Me", :name => "Moi"})  }
    assert_equal "Moi", Distribute.find(:all).last.changes['name']
  end
  
  def test_destroy 
    # Destroy case should put all distributed attribs into changes
    u = create_user
    assert_difference('Distribute.count', 1)    { assert u.destroy }
    destroy_chgs = Distribute.find(:all).last.changes
    assert_equal [['name', 'Brandon'], ["uuid", nil], ['activated', nil], ['logins', 0], ['password', 'password']].sort, destroy_chgs.sort 
  end
  
  
  def test_save_without_distributing
    assert_no_difference 'Distribute.count' do
      u = User.new(:name => 'Brandon')
      assert u.save_without_distributing
    end
  end
  
  def test_without_distributing_block
    assert_no_difference 'Distribute.count' do
      User.without_distributing { User.create(:name => 'Brandon') }
    end
  end
  
  
  def test_clears_changed_attributes_after_save
    u = User.new(:name => 'Brandon')
    assert u.changed?
    u.save
    assert !u.changed?
  end
  
  
  def test_that_changes_is_a_hash
    u = create_user
    distribute = Distribute.find(u.distributes.first.id)
    assert distribute.changes.is_a?(Hash)
  end
  
  def test_save_without_modifications
    u = create_user
    u.reload
    assert_nothing_raised do
      assert !u.changed?
      u.save!
    end
  end
  
  def test_save_and_update_with_messages
    prod = nil
    # create
    assert_difference('Distribute.count', 1)    { prod = create_product }
    assert_equal [['name', 'widget'],  ['features', 'powerpoint'], ["uuid", nil]].sort, \
          Distribute.find(:all).last.changes.sort
    # test is presence not equality because of message separator = " "
    assert /happiness/ =~ Distribute.find(:all).last.messages      
    # update
    Distribute.delete_all
    assert_difference('Distribute.count', 1)    { assert prod.update_attribute(:name, "superwidget") }
    assert_equal "superwidget", Distribute.find(:all).last.changes['name']
    assert /happiness/ =~ Distribute.find(:all).last.messages
  end
  
 
  
private

  def create_user(attrs = {})
    User.create({:name => 'Brandon', :username => 'brandon', :password => 'password'}.merge(attrs))
  end
  
  def create_product
    Product.create :name => "widget", :features => 'powerpoint', :messages_for_distribution => 'happiness'
  end

end