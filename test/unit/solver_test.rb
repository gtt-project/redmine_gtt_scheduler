require File.expand_path('../test_helper', __dir__)

class SolverTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Solver = RedmineGttScheduler::Scheduler::Solver
  Adapter = RedmineGttScheduler::Scheduler::VroomExpressAdapter

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    Issue.where(project_id: @project.id).update_all(geom: nil)
    @issue = Issue.find(1)
    @issue.update_columns(geom: factory.point(139.7, 35.68).to_s)
    @resource = build_resource(@project)
  end

  def solved_response(issue_id, vehicle_id)
    {
      'code' => 0,
      'routes' => [
        {
          'vehicle' => vehicle_id,
          'steps' => [
            {'type' => 'start', 'duration' => 0, 'arrival' => 0},
            {'type' => 'job', 'id' => issue_id, 'duration' => 300,
             'arrival' => Time.utc(2026, 8, 3, 9, 0).to_i,
             'waiting_time' => 0, 'service' => 1800}
          ]
        }
      ],
      'unassigned' => []
    }
  end

  test 'a successful solve stores assignments and payloads' do
    run = build_run(@project, @user, @day)
    transport, = stub_transport(solved_response(@issue.id, @resource.id))

    Solver.call(run, adapter: Adapter.new(transport: transport))

    run.reload
    assert_equal SchedulerRun::PROPOSED, run.status
    assert_equal 1, run.scheduler_assignments.count
    assignment = run.scheduler_assignments.first
    assert_equal @issue.id, assignment.issue_id
    assert_equal Time.utc(2026, 8, 3, 9, 0), assignment.starts_at
    assert run.request_payload.present?
    assert run.response_payload.present?
  end

  test 'a solver error fails the run with a message instead of raising' do
    run = build_run(@project, @user, @day)
    transport = ->(_body) { {'code' => 2, 'error' => 'no route found'}.to_json }

    Solver.call(run, adapter: Adapter.new(transport: transport))

    run.reload
    assert_equal SchedulerRun::FAILED, run.status
    assert_includes run.error_message, 'no route found'
  end

  test 'a run without resources fails without calling the solver' do
    @resource.update!(active: false)
    run = build_run(@project, @user, @day)
    called = false
    transport = ->(_body) { called = true; '{}' }

    Solver.call(run, adapter: Adapter.new(transport: transport))

    assert_not called
    assert_equal SchedulerRun::FAILED, run.reload.status
  end

  test 'solving again replaces the previous assignments' do
    run = build_run(@project, @user, @day)
    transport, = stub_transport(solved_response(@issue.id, @resource.id))
    adapter = Adapter.new(transport: transport)

    Solver.call(run, adapter: adapter)
    Solver.call(run, adapter: adapter)

    assert_equal 1, run.reload.scheduler_assignments.count
  end
end
