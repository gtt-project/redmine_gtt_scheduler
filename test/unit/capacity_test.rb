require File.expand_path('../test_helper', __dir__)

class CapacityTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles, :custom_fields, :custom_values

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder
  Report = RedmineGttScheduler::Scheduler::UnassignedReport

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # issues outside the fixed planning day at some point (#22).
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    @issue = Issue.find(1)
    @issue.update_columns(geom: @factory.point(139.7, 35.68).to_s)
  end

  def create_load_field
    field = IssueCustomField.create!(
      name: 'Load', field_format: 'int', is_for_all: true,
      tracker_ids: Tracker.pluck(:id)
    )
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('capacity_custom_field_id' => field.id.to_s)
    field
  end

  def set_load(issue, field, value)
    issue.custom_field_values = {field.id.to_s => value}
    issue.save!
    issue.reload
  end

  # VROOM rejects input where some jobs or vehicles carry the load
  # dimension and others do not (verified against a live solver), so once
  # any issue has load, everything must carry the arrays.
  test 'every job and vehicle carries the dimension once any load exists' do
    field = create_load_field
    set_load(@issue, field, '3')
    other = Issue.find(2)
    other.update_columns(geom: @factory.point(139.71, 35.69).to_s)
    build_resource(@project, capacity: 5)

    problem = Builder.new(build_run(@project, @user, @day)).build

    deliveries = problem.jobs.index_by(&:id).transform_values(&:delivery)
    assert_equal [3], deliveries[@issue.id]
    assert_equal [0], deliveries[other.id], 'an issue without a value counts as zero load'
    assert_equal [5], problem.vehicles.first.capacity
  end

  test 'without a configured field nothing carries the dimension' do
    build_resource(@project, capacity: 5)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_nil problem.jobs.first.delivery
    assert_nil problem.vehicles.first.capacity
  end

  # An all-zero dimension constrains nothing but still forces the arrays
  # onto every job and vehicle, so it is omitted entirely.
  test 'the dimension is omitted when no issue carries load' do
    create_load_field
    build_resource(@project, capacity: 5)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_nil problem.jobs.first.delivery
    assert_nil problem.vehicles.first.capacity
  end

  test 'a resource without a capacity gets one no route can exceed' do
    field = create_load_field
    set_load(@issue, field, '3')
    other = Issue.find(2)
    other.update_columns(geom: @factory.point(139.71, 35.69).to_s)
    set_load(other, field, '4')
    build_resource(@project, capacity: nil)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_equal [7], problem.vehicles.first.capacity
  end

  test 'a negative load counts as zero' do
    field = create_load_field
    set_load(@issue, field, '-2')
    build_resource(@project, capacity: 5)

    problem = Builder.new(build_run(@project, @user, @day)).build

    # Only this issue carries (negative) load, so the dimension stays off.
    assert_nil problem.jobs.first.delivery
  end

  test 'the request carries delivery and capacity' do
    field = create_load_field
    set_load(@issue, field, '3')
    build_resource(@project, capacity: 5)
    problem = Builder.new(build_run(@project, @user, @day)).build

    request = RedmineGttScheduler::Scheduler::VroomExpressAdapter.new(transport: ->(_) { '{}' })
                                                                 .build_request(problem)

    assert_equal [3], request['jobs'].first['delivery']
    assert_equal [5], request['vehicles'].first['capacity']
  end

  test 'a negative capacity is rejected by validation and clamped if stored' do
    resource = build_resource(@project, capacity: 5)
    resource.capacity = -3
    assert_not resource.valid?

    # Written past the validations, it must still not reach the solver.
    resource.update_column(:capacity, -3)
    field = create_load_field
    set_load(@issue, field, '2')
    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_equal [0], problem.vehicles.first.capacity
  end

  test 'a load no resource can carry is diagnosed as such' do
    field = create_load_field
    set_load(@issue, field, '10')
    build_resource(@project, capacity: 5)
    run = build_run(@project, @user, @day,
                    status: SchedulerRun::PROPOSED,
                    response_payload: {'unassigned' => [{'id' => @issue.id}]}.to_json)

    assert_equal Report::OVER_CAPACITY, Report.call(run)[@issue.id]
  end

  # The window analysis must only look at resources that could carry the
  # job, or the reason would point at the wrong resource's shift.
  test 'window diagnostics only consider resources with enough capacity' do
    field = create_load_field
    set_load(@issue, field, '10')
    @issue.update!(start_date: @day, due_date: @day,
                   start_time: '14:00', due_time: '15:00')
    # Can carry it, but works mornings only.
    build_resource(@project, name: 'Big truck',
                             capacity: 20, work_starts: '08:00', work_ends: '12:00')
    # Works the right hours, but cannot carry it.
    build_resource(@project, name: 'Small van',
                             capacity: 5, work_starts: '08:00', work_ends: '17:00')
    run = build_run(@project, @user, @day,
                    status: SchedulerRun::PROPOSED,
                    response_payload: {'unassigned' => [{'id' => @issue.id}]}.to_json)

    assert_equal Report::OUTSIDE_WORKING_HOURS, Report.call(run)[@issue.id]
  end
end
