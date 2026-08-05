require File.expand_path('../test_helper', __dir__)

class BackendRegistryTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Scheduler = RedmineGttScheduler::Scheduler
  Solver = Scheduler::Solver

  # An adapter that returns an empty but valid solution and records that
  # it was the one called.
  class RecordingAdapter < Scheduler::Adapter
    cattr_accessor :solved, default: false

    def solve(_problem)
      self.class.solved = true
      Scheduler::Solution.new(request: {}, raw: {})
    end
  end

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    enable_scheduler(@project)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    Issue.find(1).update_columns(geom: factory.point(139.7, 35.68).to_s)
    build_resource(@project)
    RecordingAdapter.solved = false
  end

  def teardown
    Scheduler.adapters.delete('recording')
  end

  test 're-registering a name replaces the class and keeps working' do
    Scheduler.register_adapter('recording', Scheduler::VroomExpressAdapter)
    # The replacement is logged (different class name) but last wins,
    # matching load-order semantics.
    Scheduler.register_adapter('recording', RecordingAdapter)

    assert_equal RecordingAdapter, Scheduler.adapter_for('recording')
  end

  test 'vroom-express is registered as the default' do
    assert_equal Scheduler::VroomExpressAdapter,
                 Scheduler.adapter_for(Scheduler::DEFAULT_ADAPTER_NAME)
    assert_equal Scheduler::DEFAULT_ADAPTER_NAME, RedmineGttScheduler.solver_backend
  end

  test 'the solver uses the configured backend' do
    Scheduler.register_adapter('recording', RecordingAdapter)
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('solver_backend' => 'recording')

    run = build_run(@project, @user, Date.new(2026, 8, 3))
    Solver.call(run)

    assert RecordingAdapter.solved, 'the registered backend must be the one called'
    assert_equal SchedulerRun::PROPOSED, run.reload.status
  end

  test 'an unknown configured backend fails the run with a clear message' do
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('solver_backend' => 'gone_solver')

    run = build_run(@project, @user, Date.new(2026, 8, 3))
    Solver.call(run)

    run.reload
    assert_equal SchedulerRun::FAILED, run.status
    assert_includes run.error_message, 'gone_solver'
  end

  test 'an explicitly injected adapter bypasses the registry' do
    transport, = stub_transport('code' => 0, 'routes' => [], 'unassigned' => [])
    run = build_run(@project, @user, Date.new(2026, 8, 3))

    Solver.call(run, adapter: Scheduler::VroomExpressAdapter.new(transport: transport))

    assert_equal SchedulerRun::PROPOSED, run.reload.status
  end
end
