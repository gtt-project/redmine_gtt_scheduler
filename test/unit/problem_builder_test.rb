require File.expand_path('../test_helper', __dir__)

class ProblemBuilderTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Fixture issues carry start/due dates relative to *today* (ERB in the
    # fixtures), while the planning day here is fixed. Clear both so the
    # suite does not start failing by itself once today passes the planning
    # day; tests that need dates set their own explicitly.
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
  end

  def place(issue, lng, lat)
    issue.update_columns(geom: @factory.point(lng, lat).to_s)
    issue.reload
  end

  test 'builds jobs from open geolocated issues and vehicles from active resources' do
    issue = Issue.find(1)
    place(issue, 139.7, 35.68)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_equal [issue.id], problem.jobs.map(&:id)
    job = problem.jobs.first
    assert_in_delta 139.7, job.location[0], 0.0001
    assert_in_delta 35.68, job.location[1], 0.0001
    assert_equal 1, problem.vehicles.size
    assert problem.solvable?
  end

  test 'issues without geometry are not part of the problem' do
    build_resource(@project)
    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_empty problem.jobs
    assert_not problem.solvable?
  end

  test 'service time comes from estimated hours with a settings fallback' do
    with_estimated = Issue.find(1)
    place(with_estimated, 139.7, 35.68)
    with_estimated.update_columns(estimated_hours: 2.0, start_date: nil, due_date: nil)
    without_estimated = Issue.find(7)
    place(without_estimated, 139.71, 35.69)
    without_estimated.update_columns(estimated_hours: nil, start_date: nil, due_date: nil)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, @day)).build
    services = problem.jobs.index_by(&:id).transform_values(&:service)

    assert_equal 7200, services[with_estimated.id]
    assert_equal RedmineGttScheduler.default_service_seconds, services[without_estimated.id]
  end

  test 'time windows come from issue datetimes and are clamped to the planning day' do
    issue = Issue.find(1)
    place(issue, 139.7, 35.68)
    issue.update!(start_date: @day, due_date: @day, start_time: '09:00', due_time: '12:00')
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, @day)).build
    window = problem.jobs.first.time_window

    assert_equal Time.utc(2026, 8, 3, 9, 0).to_i, window[0]
    assert_equal Time.utc(2026, 8, 3, 12, 0).to_i, window[1]
  end

  test 'issues whose window misses the planning day are excluded with a reason' do
    issue = Issue.find(1)
    place(issue, 139.7, 35.68)
    issue.update!(start_date: @day + 5, due_date: @day + 6)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_empty problem.jobs.select { |j| j.id == issue.id }
    assert_equal 'outside_planning_day', problem.excluded[issue.id]
  end

  test 'vehicle time windows follow the resource working hours on the planning day' do
    place(Issue.find(1), 139.7, 35.68)
    build_resource(@project, work_starts: '08:30', work_ends: '16:45')

    problem = Builder.new(build_run(@project, @user, @day)).build
    window = problem.vehicles.first.time_window

    assert_equal Time.utc(2026, 8, 3, 8, 30).to_i, window[0]
    assert_equal Time.utc(2026, 8, 3, 16, 45).to_i, window[1]
  end

  test 'single-digit working hours anchor the vehicle window correctly' do
    place(Issue.find(1), 139.7, 35.68)
    build_resource(@project, work_starts: '8:00', work_ends: '9:30')

    problem = Builder.new(build_run(@project, @user, @day)).build
    window = problem.vehicles.first.time_window

    assert_equal Time.utc(2026, 8, 3, 8, 0).to_i, window[0]
    assert_equal Time.utc(2026, 8, 3, 9, 30).to_i, window[1]
  end

  test 'inactive resources are not used as vehicles' do
    place(Issue.find(1), 139.7, 35.68)
    build_resource(@project, active: false)

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_empty problem.vehicles
    assert_not problem.solvable?
  end

  test 'the end location defaults to the start location' do
    place(Issue.find(1), 139.7, 35.68)
    build_resource(@project, end_lng: nil, end_lat: nil)

    problem = Builder.new(build_run(@project, @user, @day)).build
    vehicle = problem.vehicles.first

    assert_equal vehicle.start, vehicle.end
  end
end
