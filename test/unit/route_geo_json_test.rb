require File.expand_path('../test_helper', __dir__)

class RouteGeoJsonTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  Builder = RedmineGttScheduler::Scheduler::RouteGeoJson

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    @run = build_run(@project, @user, @day, status: SchedulerRun::PROPOSED)
  end

  def place(issue, lng, lat)
    issue.update_columns(geom: @factory.point(lng, lat).to_s)
    issue.reload
  end

  def assign(issue, resource, sequence, hour)
    @run.scheduler_assignments.create!(
      issue: issue, scheduler_resource: resource, sequence: sequence,
      starts_at: Time.utc(2026, 8, 3, hour, 0),
      ends_at: Time.utc(2026, 8, 3, hour, 30)
    )
  end

  def features_of(kind, collection)
    collection['features'].select { |f| f['geometry']['type'] == kind }
  end

  test 'one point per stop and one line per resource in visit order' do
    resource = build_resource(@project)
    first = place(Issue.find(1), 139.70, 35.68)
    second = place(Issue.find(2), 139.75, 35.70)
    assign(second, resource, 2, 10)
    assign(first, resource, 1, 9)

    collection = Builder.call(@run.scheduler_assignments.includes(:issue, :scheduler_resource))

    assert_equal 'FeatureCollection', collection['type']
    points = features_of('Point', collection)
    assert_equal [1, 2], points.map { |f| f['properties']['sequence'] }.sort
    lines = features_of('LineString', collection)
    assert_equal 1, lines.size
    # Ordered by sequence, not by insertion or issue id.
    assert_in_delta 139.70, lines.first['geometry']['coordinates'][0][0], 0.0001
    assert_in_delta 139.75, lines.first['geometry']['coordinates'][1][0], 0.0001
  end

  test 'each resource gets its own line and a distinct colour' do
    a = build_resource(@project, name: 'Crew A')
    b = build_resource(@project, name: 'Crew B')
    assign(place(Issue.find(1), 139.70, 35.68), a, 1, 9)
    assign(place(Issue.find(2), 139.71, 35.69), a, 2, 10)
    assign(place(Issue.find(3), 139.80, 35.75), b, 1, 9)
    assign(place(Issue.find(7), 139.81, 35.76), b, 2, 10)

    collection = Builder.call(@run.scheduler_assignments.includes(:issue, :scheduler_resource))
    lines = features_of('LineString', collection)

    assert_equal 2, lines.size
    assert_equal 2, lines.map { |f| f['properties']['color'] }.uniq.size
    assert_equal ['Crew A', 'Crew B'], lines.map { |f| f['properties']['resource'] }.sort
  end

  test 'a single stop yields a point but no line' do
    resource = build_resource(@project)
    assign(place(Issue.find(1), 139.70, 35.68), resource, 1, 9)

    collection = Builder.call(@run.scheduler_assignments.includes(:issue, :scheduler_resource))

    assert_equal 1, features_of('Point', collection).size
    assert_empty features_of('LineString', collection)
  end

  test 'stops whose issue lost its geometry are skipped, not fatal' do
    resource = build_resource(@project)
    assign(place(Issue.find(1), 139.70, 35.68), resource, 1, 9)
    ungeolocated = Issue.find(2)
    ungeolocated.update_columns(geom: nil)
    assign(ungeolocated, resource, 2, 10)

    collection = Builder.call(@run.scheduler_assignments.includes(:issue, :scheduler_resource))

    assert_equal 1, features_of('Point', collection).size
    assert_empty features_of('LineString', collection)
  end

  test 'colours repeat only after the palette is exhausted' do
    palette = RedmineGttScheduler::Scheduler::RouteGeoJson::COLORS
    assert_equal palette.first, Builder.color_for(0)
    assert_equal palette.first, Builder.color_for(palette.size)
    assert_equal palette.size, (0...palette.size).map { |i| Builder.color_for(i) }.uniq.size
  end
end
