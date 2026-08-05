require File.expand_path('../test_helper', __dir__)

class MultiDayTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder
  Adapter = RedmineGttScheduler::Scheduler::VroomExpressAdapter
  Solver = RedmineGttScheduler::Scheduler::Solver
  RouteGeoJson = RedmineGttScheduler::Scheduler::RouteGeoJson

  # Monday and Tuesday.
  DAY_ONE = Date.new(2026, 8, 3)
  DAY_TWO = Date.new(2026, 8, 4)

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # issues outside the fixed planning range at some point (#22).
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    @issue = Issue.find(1)
    @issue.update_columns(geom: @factory.point(139.7, 35.68).to_s)
  end

  def multi_day_run(attributes = {})
    build_run(@project, @user, DAY_ONE, {scheduled_until: DAY_TWO}.merge(attributes))
  end

  test 'the end date must not precede the start and the range is capped' do
    run = @project.scheduler_runs.build(user: @user, scheduled_on: DAY_ONE,
                                        scheduled_until: DAY_ONE - 1)
    assert_not run.valid?

    run.scheduled_until = DAY_ONE + SchedulerRun::MAX_PLANNING_DAYS
    assert_not run.valid?, 'a range longer than the cap must be rejected'

    run.scheduled_until = DAY_TWO
    assert run.valid?
  end

  test 'an end date equal to the start is a single-day run' do
    run = build_run(@project, @user, DAY_ONE, scheduled_until: DAY_ONE)

    assert_not run.multi_day?
    assert_equal [DAY_ONE], run.planning_days
  end

  test 'a multi-day problem has one vehicle per resource per working day' do
    resource = build_resource(@project)

    problem = Builder.new(multi_day_run).build

    assert_equal 2, problem.vehicles.size
    # Synthetic ids, mapped back to the resource and its day.
    assert_equal [1, 2], problem.vehicles.map(&:id)
    assert_equal [resource.id, DAY_ONE], problem.vehicle_index[1]
    assert_equal [resource.id, DAY_TWO], problem.vehicle_index[2]
    # The second vehicle's window is anchored on the second day.
    assert_equal Time.utc(2026, 8, 4, 8, 0).to_i, problem.vehicles.last.time_window[0]
  end

  test 'working days are honoured per day of the range' do
    # Works Mondays only, so Tuesday contributes no vehicle.
    build_resource(@project, working_days: [1])

    problem = Builder.new(multi_day_run).build

    assert_equal 1, problem.vehicles.size
  end

  test 'a single-day run keeps resource ids as vehicle ids' do
    resource = build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY_ONE)).build

    assert_equal [resource.id], problem.vehicles.map(&:id)
    assert_empty problem.vehicle_index
  end

  test 'issue windows are clamped to the whole range' do
    build_resource(@project)
    @issue.update!(start_date: DAY_TWO, due_date: DAY_TWO,
                   start_time: '09:00', due_time: '12:00')

    problem = Builder.new(multi_day_run).build

    assert_equal [@issue.id], problem.jobs.map(&:id)
    assert_equal Time.utc(2026, 8, 4, 9, 0).to_i, problem.jobs.first.time_window[0]
  end

  test 'an issue outside the range is excluded with a range reason' do
    build_resource(@project)
    @issue.update!(start_date: DAY_ONE + 10, due_date: DAY_ONE + 11)

    problem = Builder.new(multi_day_run).build

    assert_equal 'outside_planning_range', problem.excluded[@issue.id]
  end

  test 'assignments map the synthetic vehicle back to the resource' do
    resource = build_resource(@project)
    run = multi_day_run
    # Vehicle 2 is the resource's Tuesday vehicle.
    response = {
      'code' => 0,
      'routes' => [
        {'vehicle' => 2, 'steps' => [
          {'type' => 'job', 'id' => @issue.id, 'duration' => 0,
           'arrival' => Time.utc(2026, 8, 4, 9, 0).to_i,
           'waiting_time' => 0, 'service' => 1800}
        ]}
      ],
      'unassigned' => []
    }
    transport, = stub_transport(response)

    Solver.call(run, adapter: Adapter.new(transport: transport))

    run.reload
    assignment = run.scheduler_assignments.first
    assert_equal resource.id, assignment.scheduler_resource_id
    assert_equal Time.utc(2026, 8, 4, 9, 0), assignment.starts_at
    # The stored map lets payload readers translate vehicle ids too.
    assert_equal [resource.id, DAY_TWO.iso8601], run.parsed_vehicle_map[2]
  end

  test 'route geometries are grouped per resource with their day' do
    resource = build_resource(@project)
    run = multi_day_run
    run.update!(
      vehicle_map: {1 => [resource.id, DAY_ONE.iso8601], 2 => [resource.id, DAY_TWO.iso8601]}.to_json,
      response_payload: {
        'routes' => [
          {'vehicle' => 1, 'geometry' => 'abc'},
          {'vehicle' => 2, 'geometry' => 'def'}
        ]
      }.to_json
    )

    grouped = run.route_geometries_by_resource

    assert_equal [{'date' => DAY_ONE.iso8601, 'geometry' => 'abc'},
                  {'date' => DAY_TWO.iso8601, 'geometry' => 'def'}],
                 grouped[resource.id]
  end

  test 'straight legs never join stops of different days' do
    resource = build_resource(@project)
    run = multi_day_run(status: SchedulerRun::PROPOSED)
    second = Issue.find(2)
    second.update_columns(geom: @factory.point(139.71, 35.69).to_s)
    third = Issue.find(3)
    third.update_columns(geom: @factory.point(139.72, 35.70).to_s)
    fourth = Issue.find(7)
    fourth.update_columns(geom: @factory.point(139.73, 35.71).to_s)
    # Two stops on Monday, two on Tuesday; sequences restart per day.
    [[@issue, DAY_ONE, 1, 9], [second, DAY_ONE, 2, 11],
     [third, DAY_TWO, 1, 9], [fourth, DAY_TWO, 2, 11]].each do |issue, day, sequence, hour|
      run.scheduler_assignments.create!(
        issue: issue, scheduler_resource: resource, sequence: sequence,
        starts_at: Time.utc(day.year, day.month, day.day, hour, 0),
        ends_at: Time.utc(day.year, day.month, day.day, hour, 30)
      )
    end

    collection = RouteGeoJson.call(run.scheduler_assignments.includes(:issue, :scheduler_resource))
    lines = collection['features'].select { |f| f['geometry']['type'] == 'LineString' }

    assert_equal 2, lines.size, 'one line per day, not one line joining all four stops'
    assert(lines.all? { |line| line['geometry']['coordinates'].size == 2 })
    # Same resource, so both days share one colour.
    assert_equal 1, lines.map { |line| line['properties']['color'] }.uniq.size
  end

  test 'a run form submission with an end date creates a range' do
    run = multi_day_run

    assert run.multi_day?
    assert_equal [DAY_ONE, DAY_TWO], run.planning_days
  end
end
