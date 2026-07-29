require File.expand_path('../test_helper', __dir__)

class SchedulerTimelineTest < ActionView::TestCase
  include SchedulerTestHelper
  include SchedulerRunsHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @resource = build_resource(@project)
    @run = build_run(@project, @user, @day, status: SchedulerRun::PROPOSED)
  end

  def assignment(sequence, from, to, issue_id: 1)
    @run.scheduler_assignments.create!(
      issue_id: issue_id, scheduler_resource: @resource, sequence: sequence,
      starts_at: from, ends_at: to
    )
  end

  test 'no assignments yields no timeline' do
    assert_nil scheduler_timeline([])
  end

  test 'the window snaps to whole hours covering every assignment' do
    a = assignment(1, Time.utc(2026, 8, 3, 9, 15), Time.utc(2026, 8, 3, 10, 45))
    timeline = scheduler_timeline([a])

    zone = RedmineGttScheduler.reference_zone
    assert_equal zone.local(2026, 8, 3, 9, 0), timeline[:from]
    assert_equal zone.local(2026, 8, 3, 11, 0), timeline[:to]
    assert_equal 2, timeline[:hours]
    assert_equal %w[09:00 10:00 11:00], timeline[:ticks].map { |t| t[:label] }
  end

  test 'bars are positioned as percentages of the window' do
    a = assignment(1, Time.utc(2026, 8, 3, 9, 0), Time.utc(2026, 8, 3, 10, 0))
    b = assignment(2, Time.utc(2026, 8, 3, 11, 0), Time.utc(2026, 8, 3, 12, 0), issue_id: 2)
    timeline = scheduler_timeline([a, b])

    # Window is 09:00-12:00, so each hour is a third of the track.
    assert_equal 3, timeline[:hours]
    first, second = timeline[:bars]
    assert_in_delta 0.0, first[:left], 0.01
    assert_in_delta 33.33, first[:width], 0.01
    assert_in_delta 66.67, second[:left], 0.01
    assert_in_delta 33.33, second[:width], 0.01
  end

  test 'a zero-duration stop still gets a visible sliver' do
    at = Time.utc(2026, 8, 3, 9, 30)
    timeline = scheduler_timeline([assignment(1, at, at)])

    assert_operator timeline[:bars].first[:width], :>, 0
  end

  test 'bars never overflow the track' do
    a = assignment(1, Time.utc(2026, 8, 3, 9, 0), Time.utc(2026, 8, 3, 17, 0))
    timeline = scheduler_timeline([a])
    bar = timeline[:bars].first

    assert_operator bar[:left] + bar[:width], :<=, 100.0
  end

  test 'the axis is rendered in the reference zone, not UTC' do
    enable_scheduler(@project)
    Setting.plugin_redmine_issue_datetime = {
      'tracker_ids' => @project.trackers.map(&:id).map(&:to_s),
      'time_step' => '15', 'reference_zone' => 'Tokyo'
    }
    a = assignment(1, Time.utc(2026, 8, 3, 0, 0), Time.utc(2026, 8, 3, 1, 0))

    # 00:00 UTC is 09:00 in Tokyo; the axis must say 09:00.
    assert_equal '09:00', scheduler_timeline([a])[:ticks].first[:label]
  end
end
