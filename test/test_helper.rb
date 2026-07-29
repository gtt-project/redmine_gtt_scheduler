require File.expand_path('../../../test/test_helper', __dir__)

module SchedulerTestHelper
  # Enables the scheduler module and the time fields of redmine_issue_datetime
  # for the given project and trackers.
  def enable_scheduler(project, tracker_ids: nil)
    project.enabled_module_names = project.enabled_module_names + ['gtt_scheduler']
    Setting.plugin_redmine_issue_datetime = {
      'tracker_ids' => Array(tracker_ids || project.trackers.map(&:id)).map(&:to_s),
      'time_step' => '15',
      'reference_zone' => 'UTC'
    }
  end

  def build_resource(project, attributes = {})
    project.scheduler_resources.create!({
      name: 'Crew A',
      start_lng: 139.7,
      start_lat: 35.68,
      work_starts: '08:00',
      work_ends: '17:00',
      active: true
    }.merge(attributes))
  end

  def build_run(project, user, date, attributes = {})
    project.scheduler_runs.create!({
      user: user,
      scheduled_on: date,
      status: SchedulerRun::DRAFT
    }.merge(attributes))
  end

  # A transport stub for VroomExpressAdapter: records the request and
  # returns the given response body.
  def stub_transport(response)
    requests = []
    transport = lambda do |body|
      requests << JSON.parse(body)
      response.to_json
    end
    [transport, requests]
  end
end
