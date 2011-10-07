require File.expand_path('../../test_helper', __FILE__)
require 'data_graph'

class EagerLoadingTest < Test::Unit::TestCase
  include DatabaseTest

  class Emp < ActiveRecord::Base
    set_table_name 'emps'
    belongs_to :dept, :conditions => "depts.name like '%c%'"
    belongs_to :job, :select => 'jobs.name'
  end

  class Job < ActiveRecord::Base
    set_table_name 'jobs'
    has_many :emps
    has_many :depts, :through => :emps
  end

  class Dept < ActiveRecord::Base
    set_table_name 'depts'
    has_many :emps, :order => 'emps.first_name'
  end

  # NoMethodError occurs because job association doesn't select for the
  # reference key (id) - belongs_to :job, :select => 'jobs.id, jobs.name'
  def test_eager_loading_with_select_on_association
    assert_equal 'President', Emp.find(:first).job.name
    assert_raises(NoMethodError) { Emp.find(:first, :include => :job).job.name }
    assert_equal 'President', Emp.find(:first, :select => 'jobs.name', :include => :job).job.name
  end

  # Illustrates variability regarding where conditions are evaluated (not
  # exactly sure why).  Note the second variation has become more consistent
  # in AR3.  Before it would add a nil between "Research" and "Accounting"
  def test_eager_loading_with_condition_on_hmt_association
    depts = Job.find(4).depts
    assert_equal ["Research", "Research", "Accounting"], depts.collect {|dept| dept.name }

    depts = Job.find(4, :include => :depts).depts
    assert_equal ["Research", "Research", "Accounting"], depts.collect {|dept| dept.nil? ? nil : dept.name }

    depts = Job.find(4, :include => :depts, :conditions => "depts.name like '%c%'").depts
    assert_equal ["Research", "Accounting"], depts.collect {|dept| dept.name }
  end

  # Uh... not sure what's going on here.
  def test_eager_loading_with_order
    emps = Dept.find(:first).emps
    assert_equal ["Carla", "Kim", "Michelle"], emps.collect {|emp| emp.first_name }

    emps = Dept.find(:first, :include => :emps).emps
    assert_equal ["Carla", "Kim", "Michelle"], emps.collect {|emp| emp.first_name }

    emps = Dept.find(:first, :include => :emps, :order => 'emps.first_name').emps
    assert_equal [], emps.collect {|emp| emp.first_name }
  end
end