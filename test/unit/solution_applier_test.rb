require File.expand_path('../test_helper', __dir__)

class SolutionApplierTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :journals, :journal_details, :enumerations,
           :enabled_modules, :members, :member_roles, :roles, :watchers

  Applier = RedmineGttScheduler::Scheduler::SolutionApplier

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @issue = Issue.find(1)
    @resource = build_resource(@project, user: User.find(3))
    @run = build_run(@project, @user, @day, status: SchedulerRun::PROPOSED)
    @run.scheduler_assignments.create!(
      issue: @issue, scheduler_resource: @resource, sequence: 1,
      starts_at: Time.utc(2026, 8, 3, 9, 0),
      ends_at: Time.utc(2026, 8, 3, 10, 30),
      travel_seconds: 600
    )
  end

  test 'applying writes dates, times, and assignee' do
    result = Applier.call(@run, @user)

    assert result.success?, result.message
    @issue.reload
    assert_equal @day, @issue.start_date
    assert_equal @day, @issue.due_date
    assert_equal Time.utc(2026, 8, 3, 9, 0), @issue.issue_datetime.starts_at
    assert_equal Time.utc(2026, 8, 3, 10, 30), @issue.issue_datetime.ends_at
    assert_equal User.find(3), @issue.assigned_to
    assert_equal SchedulerRun::APPLIED, @run.reload.status
  end

  test 'applying journalizes the change with a run reference' do
    Applier.call(@run, @user)

    journal = @issue.reload.journals.last
    assert_equal @user, journal.user
    assert_includes journal.notes, "##{@run.id}"
    assert journal.details.any? { |d| d.prop_key == 'start_time' }
  end

  test 'only proposed runs can be applied' do
    @run.update!(status: SchedulerRun::APPLIED)

    result = Applier.call(@run, @user)

    assert_not result.success?
  end

  test 'applying is blocked when an issue is not editable by the user' do
    Role.non_member.remove_permission!(:edit_issues)
    unprivileged = User.find(7)
    assert_not @issue.attributes_editable?(unprivileged)

    result = Applier.call(@run, unprivileged)

    assert_not result.success?
    assert_includes result.message, "##{@issue.id}"
    assert_nil @issue.reload.issue_datetime
    assert_equal SchedulerRun::PROPOSED, @run.reload.status
  end

  test 'a normal apply carries no warning' do
    result = Applier.call(@run, @user)

    assert result.success?
    assert_nil result.warning
  end

  # redmine_issue_datetime ignores the time setters for trackers it is not
  # enabled for; the dates and the assignee are still written, but the times
  # are lost. The dispatcher must be told.
  test 'applying warns when a tracker cannot store times' do
    Setting.plugin_redmine_issue_datetime = {
      'tracker_ids' => [], 'time_step' => '15', 'reference_zone' => 'UTC'
    }

    result = Applier.call(@run, @user)

    assert result.success?, result.message
    assert_includes result.warning, "##{@issue.id}"
    @issue.reload
    assert_equal @day, @issue.start_date
    assert_nil @issue.issue_datetime, 'times cannot be stored for a disabled tracker'
  end

  test 'a resource without a linked user leaves the assignee untouched' do
    @issue.update_columns(assigned_to_id: User.find(2).id)
    @resource.update!(user: nil)

    assert Applier.call(@run, @user).success?
    assert_equal User.find(2), @issue.reload.assigned_to
  end
end
