require File.expand_path('../test_helper', __dir__)

class BreaksTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder
  Adapter = RedmineGttScheduler::Scheduler::VroomExpressAdapter

  DAY_ONE = Date.new(2026, 8, 3)
  DAY_TWO = Date.new(2026, 8, 4)

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

  def break_resource(attributes = {})
    build_resource(@project, {
      break_starts: '12:00', break_ends: '13:00', break_minutes: 45
    }.merge(attributes))
  end

  test 'a configured break becomes a vehicle break anchored on the day' do
    break_resource

    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build
    breaks = problem.vehicles.first.breaks

    assert_equal 1, breaks.size
    assert_equal 45 * 60, breaks.first[:service]
    assert_equal [Time.utc(2026, 8, 3, 12, 0).to_i, Time.utc(2026, 8, 3, 13, 0).to_i],
                 breaks.first[:time_window]
  end

  test 'a resource without a break contributes none' do
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build

    assert_nil problem.vehicles.first.breaks
  end

  test 'multi-day runs anchor the break on each day' do
    break_resource

    run = build_run(@project, @user, DAY_ONE, scheduled_until: DAY_TWO)
    problem = Builder.new(run).build

    windows = problem.vehicles.map { |v| v.breaks.first[:time_window].first }
    assert_equal [Time.utc(2026, 8, 3, 12, 0).to_i, Time.utc(2026, 8, 4, 12, 0).to_i],
                 windows
  end

  test 'the request carries the break in VROOM shape' do
    break_resource
    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build

    request = Adapter.new(transport: ->(_) { '{}' }).build_request(problem)
    brk = request['vehicles'].first['breaks'].first

    assert_equal 1, brk['id']
    assert_equal 45 * 60, brk['service']
    assert_equal 1, brk['time_windows'].size
  end

  # Break steps carry cumulative travel like every step, so the travel of
  # the job after the break must not include what accrued before it.
  test 'a break step in the response does not distort travel times' do
    resource = break_resource
    run = build_run(@project, @user, DAY_ONE)
    response = {
      'code' => 0,
      'routes' => [
        {'vehicle' => resource.id, 'steps' => [
          {'type' => 'start', 'duration' => 0, 'arrival' => 0},
          {'type' => 'job', 'id' => 1, 'duration' => 600,
           'arrival' => Time.utc(2026, 8, 3, 9, 0).to_i, 'waiting_time' => 0, 'service' => 1800},
          {'type' => 'break', 'id' => 1, 'duration' => 900,
           'arrival' => Time.utc(2026, 8, 3, 12, 0).to_i, 'waiting_time' => 0, 'service' => 2700},
          {'type' => 'job', 'id' => 2, 'duration' => 1200,
           'arrival' => Time.utc(2026, 8, 3, 13, 0).to_i, 'waiting_time' => 0, 'service' => 1800}
        ]}
      ],
      'unassigned' => []
    }
    transport, = stub_transport(response)

    RedmineGttScheduler::Scheduler::Solver.call(run, adapter: Adapter.new(transport: transport))

    travels = run.reload.scheduler_assignments.order(:sequence).pluck(:travel_seconds)
    # 600 to the first job; the break added 300 (600 -> 900); 300 more to
    # the second job (900 -> 1200).
    assert_equal [600, 300], travels
  end

  # Values written past the validations must not reach the solver as a
  # zero-length or inverted break.
  test 'a malformed stored break is omitted rather than sent to the solver' do
    resource = break_resource
    resource.update_columns(break_starts: '14:00', break_ends: '12:00')

    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build

    assert_nil problem.vehicles.first.breaks
  end

  test 'a non-positive stored duration is omitted too' do
    resource = break_resource
    resource.update_columns(break_minutes: 0)

    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build

    assert_nil problem.vehicles.first.breaks
  end

  test 'a partial break configuration is rejected' do
    resource = build_resource(@project)
    resource.break_starts = '12:00'

    assert_not resource.valid?
  end

  test 'a break window in the wrong order is rejected' do
    resource = build_resource(@project)
    resource.assign_attributes(break_starts: '13:00', break_ends: '12:00',
                               break_minutes: 30)

    assert_not resource.valid?
  end
end
