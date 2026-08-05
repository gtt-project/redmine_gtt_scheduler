require File.expand_path('../test_helper', __dir__)

class SchedulerRunResourcesTest < ActiveSupport::TestCase
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
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # the issue outside the fixed planning day at some point (#22).
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    Issue.find(1).update_columns(geom: factory.point(139.7, 35.68).to_s)
  end

  test 'a run with no selection falls back to every active resource' do
    a = build_resource(@project, name: 'Crew A')
    b = build_resource(@project, name: 'Crew B')
    run = build_run(@project, @user, @day)

    assert_not run.resource_selection?
    assert_equal [a.id, b.id].sort, run.resources_for_solving.map(&:id).sort
    assert_equal 2, Builder.new(run).build.vehicles.size
  end

  test 'a selection limits the vehicles the solver sees' do
    a = build_resource(@project, name: 'Crew A')
    build_resource(@project, name: 'Crew B')
    run = build_run(@project, @user, @day)
    run.selected_resources = [a]

    assert run.resource_selection?
    assert_equal [a.id], Builder.new(run).build.vehicles.map(&:id)
  end

  test 'a selected resource that has since been deactivated is dropped' do
    a = build_resource(@project, name: 'Crew A')
    b = build_resource(@project, name: 'Crew B')
    run = build_run(@project, @user, @day)
    run.selected_resources = [a, b]
    b.update!(active: false)

    assert_equal [a.id], run.reload.resources_for_solving.map(&:id)
  end

  test 'deactivating every selected resource does not silently widen the run' do
    a = build_resource(@project, name: 'Crew A')
    build_resource(@project, name: 'Crew B')
    run = build_run(@project, @user, @day)
    run.selected_resources = [a]
    a.update!(active: false)

    # The fallback exists for runs that never had a selection. A run that made
    # one must not quietly pick up resources the dispatcher excluded, so it ends
    # up with no vehicles and the solver reports it as unsolvable.
    assert_empty run.reload.resources_for_solving
    assert_not Builder.new(run.reload).build.solvable?
  end

  test 'the same resource cannot be selected twice' do
    a = build_resource(@project)
    run = build_run(@project, @user, @day)
    run.scheduler_run_resources.create!(scheduler_resource: a)

    duplicate = run.scheduler_run_resources.build(scheduler_resource: a)

    assert_not duplicate.valid?
  end

  test 'discarding a run removes its selection rows but not the resources' do
    a = build_resource(@project)
    run = build_run(@project, @user, @day)
    run.selected_resources = [a]

    assert_difference 'SchedulerRunResource.count', -1 do
      assert_no_difference 'SchedulerResource.count' do
        run.destroy
      end
    end
  end
end
