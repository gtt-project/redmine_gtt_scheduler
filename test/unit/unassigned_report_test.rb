require File.expand_path('../test_helper', __dir__)

class UnassignedReportTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Report = RedmineGttScheduler::Scheduler::UnassignedReport

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    Issue.where(project_id: @project.id).update_all(geom: nil)
    @issue = Issue.find(1)
    @issue.update_columns(geom: factory.point(139.7, 35.68).to_s,
                          start_date: nil, due_date: nil, estimated_hours: nil)
    @issue.reload
  end

  # The report reads the unassigned ids back out of the stored response, which is
  # how the run records them.
  def run_with_unassigned(issue_ids, attributes = {})
    build_run(@project, @user, @day, {
      status: SchedulerRun::PROPOSED,
      response_payload: {'unassigned' => issue_ids.map { |id| {'id' => id} }}.to_json
    }.merge(attributes))
  end

  test 'no unassigned issues yields an empty report and does no work' do
    assert_empty Report.call(run_with_unassigned([]))
  end

  test 'a window outside every working shift is reported as such' do
    build_resource(@project, work_starts: '08:00', work_ends: '12:00')
    @issue.update!(start_date: @day, due_date: @day, start_time: '14:00', due_time: '15:00')

    report = Report.call(run_with_unassigned([@issue.id]))

    assert_equal Report::OUTSIDE_WORKING_HOURS, report[@issue.id]
  end

  test 'a task longer than any shift is reported as such' do
    build_resource(@project, work_starts: '08:00', work_ends: '09:00')
    @issue.update_columns(estimated_hours: 4.0)

    report = Report.call(run_with_unassigned([@issue.id]))

    assert_equal Report::LONGER_THAN_SHIFT, report[@issue.id]
  end

  test 'a task that simply did not fit is distinguished from an impossible one' do
    build_resource(@project, work_starts: '08:00', work_ends: '17:00')
    @issue.update_columns(estimated_hours: 1.0)

    report = Report.call(run_with_unassigned([@issue.id]))

    assert_equal Report::NO_ROOM, report[@issue.id]
  end

  test 'an id that is not part of the problem is reported as unknown' do
    build_resource(@project)

    report = Report.call(run_with_unassigned([999_999]))

    assert_equal Report::UNKNOWN, report[999_999]
  end

  test 'no resources at all yields unknown rather than a misleading reason' do
    report = Report.call(run_with_unassigned([@issue.id]))

    assert_equal Report::UNKNOWN, report[@issue.id]
  end
end
