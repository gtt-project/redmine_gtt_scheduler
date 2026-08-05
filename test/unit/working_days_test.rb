require File.expand_path('../test_helper', __dir__)

class WorkingDaysTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder

  # 2026-08-03 is a Monday (cwday 1).
  MONDAY = Date.new(2026, 8, 3)
  SUNDAY = Date.new(2026, 8, 9)

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    enable_scheduler(@project)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # issues outside the fixed planning day at some point (#22).
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    Issue.find(1).update_columns(geom: factory.point(139.7, 35.68).to_s)
  end

  test 'no selection means the resource works every day' do
    resource = build_resource(@project)

    assert_equal [], resource.working_days
    assert resource.works_on?(MONDAY)
    assert resource.works_on?(SUNDAY)
  end

  test 'a selection restricts the days' do
    resource = build_resource(@project, working_days: [1, 2, 3, 4, 5])

    assert resource.works_on?(MONDAY)
    assert_not resource.works_on?(SUNDAY)
  end

  test 'the writer normalizes form input' do
    resource = build_resource(@project, working_days: ['', '5', '1', '1', '9', 'x'])

    # Sorted, unique, only valid ISO weekdays; the blank from the hidden
    # field and out-of-range values are dropped.
    assert_equal [1, 5], resource.reload.working_days
  end

  test 'a resource not working the planning day contributes no vehicle' do
    build_resource(@project, name: 'Weekday crew', working_days: [1, 2, 3, 4, 5])
    sunday_run = build_run(@project, @user, SUNDAY)

    problem = Builder.new(sunday_run).build

    assert_empty problem.vehicles
    assert_not problem.solvable?
  end

  test 'a resource working the planning day is planned as before' do
    build_resource(@project, name: 'Weekday crew', working_days: [1, 2, 3, 4, 5])
    monday_run = build_run(@project, @user, MONDAY)

    problem = Builder.new(monday_run).build

    assert_equal 1, problem.vehicles.size
  end

  test 'legacy rows with no stored value keep the old behaviour' do
    resource = build_resource(@project)
    resource.update_column(:working_days, nil)

    problem = Builder.new(build_run(@project, @user, SUNDAY)).build

    assert_equal 1, problem.vehicles.size
  end
end
