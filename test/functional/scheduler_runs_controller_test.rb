require File.expand_path('../test_helper', __dir__)

class SchedulerRunsControllerTest < Redmine::ControllerTest
  include SchedulerTestHelper

  tests SchedulerRunsController

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    enable_scheduler(@project)
    Role.find(1).add_permission!(:view_scheduler, :manage_scheduler)
    @request.session[:user_id] = @user.id
  end

  test 'index lists the runs of the project' do
    run = build_run(@project, @user, Date.new(2026, 8, 3))

    get :index, params: {project_id: @project.identifier}

    assert_response :success
    assert_select "a[href=?]", "/projects/#{@project.identifier}/scheduler_runs/#{run.id}"
  end

  test 'index paginates instead of capping the list' do
    with_settings per_page_options: '1,25' do
      3.times { |i| build_run(@project, @user, Date.new(2026, 8, 3) + i) }

      get :index, params: {project_id: @project.identifier, per_page: 1, page: 2}

      assert_response :success
      # Newest first, so page 2 at one per page is the second-newest run.
      assert_select 'table.list tbody tr', count: 1
      assert_select 'span.pagination'
    end
  end

  test 'index shows the assignment count of a run' do
    resource = build_resource(@project)
    run = build_run(@project, @user, Date.new(2026, 8, 3), status: SchedulerRun::PROPOSED)
    run.scheduler_assignments.create!(
      issue: Issue.find(1), scheduler_resource: resource, sequence: 1,
      starts_at: Time.utc(2026, 8, 3, 9, 0), ends_at: Time.utc(2026, 8, 3, 10, 0)
    )

    get :index, params: {project_id: @project.identifier}

    assert_response :success
    assert_select 'td', text: '1', minimum: 1
  end

  test 'new renders the run form' do
    get :new, params: {project_id: @project.identifier}

    assert_response :success
    assert_select 'input[name=?]', 'scheduler_run[scheduled_on]'
  end

  test 'create enqueues a solve job and redirects to the run' do
    # The app runs jobs inline in test, so stub instead of letting the
    # solver be called for real.
    SchedulerSolveJob.expects(:perform_later).once

    post :create, params: {
      project_id: @project.identifier,
      scheduler_run: {scheduled_on: '2026-08-03'}
    }

    run = @project.scheduler_runs.last
    assert_redirected_to "/projects/#{@project.identifier}/scheduler_runs/#{run.id}"
    assert_equal Date.new(2026, 8, 3), run.scheduled_on
    assert_equal @user, run.user
  end

  test 'show renders assignments of a proposed run' do
    resource = build_resource(@project)
    run = build_run(@project, @user, Date.new(2026, 8, 3), status: SchedulerRun::PROPOSED)
    run.scheduler_assignments.create!(
      issue: Issue.find(1), scheduler_resource: resource, sequence: 1,
      starts_at: Time.utc(2026, 8, 3, 9, 0), ends_at: Time.utc(2026, 8, 3, 10, 0)
    )

    get :show, params: {project_id: @project.identifier, id: run.id}

    assert_response :success
    assert_select 'h3', text: resource.name
    # The legend is filled in by scheduler_map.js on redmine_gtt's map-ready
    # event; it ships hidden so no dead controls appear if that hook is gone.
    assert_select 'div#scheduler-map-legend[hidden]'
    assert_select 'script[src*=?]', 'scheduler_map'
    # rails-ujs turns these into POSTs; core uses the same pattern.
    assert_select "a[data-method=post][href=?]",
                  "/projects/#{@project.identifier}/scheduler_runs/#{run.id}/apply"
    assert_select "a[data-method=post][href=?]",
                  "/projects/#{@project.identifier}/scheduler_runs/#{run.id}/discard"
  end

  test 'show groups a multi-day run by day within each resource' do
    resource = build_resource(@project)
    run = build_run(@project, @user, Date.new(2026, 8, 10),
                    scheduled_until: Date.new(2026, 8, 11),
                    status: SchedulerRun::PROPOSED)
    # Sequences restart per day, so each day must get its own table.
    [[1, Date.new(2026, 8, 10)], [1, Date.new(2026, 8, 11)]].each_with_index do |(sequence, day), i|
      run.scheduler_assignments.create!(
        issue: Issue.find(i + 1), scheduler_resource: resource, sequence: sequence,
        starts_at: Time.utc(day.year, day.month, day.day, 9, 0),
        ends_at: Time.utc(day.year, day.month, day.day, 10, 0)
      )
    end

    get :show, params: {project_id: @project.identifier, id: run.id}

    assert_response :success
    assert_select 'h4.scheduler-day', count: 2
    assert_select 'table.list tbody tr', count: 2
  end

  test 'discard marks a proposed run as discarded' do
    run = build_run(@project, @user, Date.new(2026, 8, 3), status: SchedulerRun::PROPOSED)

    post :discard, params: {project_id: @project.identifier, id: run.id}

    assert_redirected_to "/projects/#{@project.identifier}/scheduler_runs"
    assert_equal SchedulerRun::DISCARDED, run.reload.status
  end

  test 'members without the permission are denied' do
    Role.find(1).remove_permission!(:view_scheduler, :manage_scheduler)

    get :index, params: {project_id: @project.identifier}

    assert_response :forbidden
  end

  test 'the module must be enabled' do
    @project.enabled_module_names = @project.enabled_module_names - ['gtt_scheduler']

    get :index, params: {project_id: @project.identifier}

    assert_response :forbidden
  end
end
