require File.expand_path('../test_helper', __dir__)

class ShipmentsTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :issue_relations, :enumerations,
           :enabled_modules, :members, :member_roles, :roles,
           :custom_fields, :custom_values

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder
  Adapter = RedmineGttScheduler::Scheduler::VroomExpressAdapter
  Solver = RedmineGttScheduler::Scheduler::Solver

  DAY = Date.new(2026, 8, 3)

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # issues outside the fixed planning day at some point (#22). Fixture
    # relations are cleared so only the pairs each test creates count.
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil, estimated_hours: nil)
    IssueRelation.delete_all
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('shipment_relation_type' => 'blocks')
  end

  def place(issue, lng, lat)
    issue.update_columns(geom: @factory.point(lng, lat).to_s)
    issue.reload
  end

  # The pickup issue blocks the delivery issue.
  def pair(pickup, delivery, type: 'blocks')
    IssueRelation.create!(issue_from: pickup, issue_to: delivery,
                          relation_type: type)
  end

  test 'a blocks relation between two plannable issues becomes a shipment' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    pair(pickup, delivery)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY)).build

    assert_empty problem.jobs, 'both stops must leave the plain job list'
    assert_equal 1, problem.shipments.size
    shipment = problem.shipments.first
    assert_equal pickup.id, shipment.pickup.id
    assert_equal delivery.id, shipment.delivery.id
    assert problem.solvable?, 'a problem with only shipments is solvable'
  end

  test 'without the setting relations do not pair anything' do
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('shipment_relation_type' => '')
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    pair(pickup, delivery)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY)).build

    assert_equal 2, problem.jobs.size
    assert_empty problem.shipments
  end

  test 'a relation of a different type does not pair' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    pair(pickup, delivery, type: 'relates')
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY)).build

    assert_equal 2, problem.jobs.size
    assert_empty problem.shipments
  end

  test 'an issue in two shipment relations is excluded as ambiguous' do
    a = place(Issue.find(1), 139.70, 35.68)
    b = place(Issue.find(2), 139.75, 35.70)
    c = place(Issue.find(3), 139.80, 35.72)
    pair(a, b)
    pair(a, c)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY)).build

    assert_empty problem.shipments
    assert_equal 'ambiguous_shipment', problem.excluded[a.id]
    assert_equal 'ambiguous_shipment', problem.excluded[b.id]
    assert_equal 'ambiguous_shipment', problem.excluded[c.id]
  end

  test 'a stop whose partner is not plannable is excluded, not planned alone' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = Issue.find(2) # no geometry, so not part of the problem
    pair(pickup, delivery)
    build_resource(@project)

    problem = Builder.new(build_run(@project, @user, DAY)).build

    assert_empty problem.shipments
    assert_empty problem.jobs
    assert_equal 'shipment_partner_excluded', problem.excluded[pickup.id]
  end

  test 'the pair shares skills and moves the delivery load' do
    skills_field = IssueCustomField.create!(
      name: 'Required skills', field_format: 'list', multiple: true,
      possible_values: %w[crane forklift], is_for_all: true,
      tracker_ids: Tracker.pluck(:id)
    )
    load_field = IssueCustomField.create!(
      name: 'Load', field_format: 'int', is_for_all: true,
      tracker_ids: Tracker.pluck(:id)
    )
    Setting.plugin_redmine_gtt_scheduler = Setting.plugin_redmine_gtt_scheduler.merge(
      'skills_custom_field_id' => skills_field.id.to_s,
      'capacity_custom_field_id' => load_field.id.to_s
    )
    pickup = place(Issue.find(1), 139.70, 35.68)
    pickup.custom_field_values = {skills_field.id.to_s => ['crane']}
    pickup.save!
    delivery = place(Issue.find(2), 139.75, 35.70)
    delivery.custom_field_values = {skills_field.id.to_s => ['forklift'],
                                    load_field.id.to_s => '3'}
    delivery.save!
    pair(pickup.reload, delivery.reload)
    build_resource(@project, skills: %w[crane forklift], capacity: 5)

    problem = Builder.new(build_run(@project, @user, DAY)).build
    shipment = problem.shipments.first

    # Union of both stops' skills; ids from the per-problem map.
    assert_equal shipment.pickup.skills, shipment.delivery.skills
    assert_equal 2, shipment.skills.size
    assert_equal [3], shipment.amount
  end

  test 'the request carries the shipment in VROOM shape' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    pair(pickup, delivery)
    build_resource(@project)
    problem = Builder.new(build_run(@project, @user, DAY)).build

    request = Adapter.new(transport: ->(_) { '{}' }).build_request(problem)

    assert_empty request['jobs']
    shipment = request['shipments'].first
    assert_equal pickup.id, shipment['pickup']['id']
    assert_equal delivery.id, shipment['delivery']['id']
    assert shipment['pickup'].key?('time_windows')
    assert_not shipment.key?('amount'), 'no amount without the capacity feature'
  end

  test 'pickup and delivery steps become assignments with their kind' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    pair(pickup, delivery)
    resource = build_resource(@project)
    run = build_run(@project, @user, DAY)
    response = {
      'code' => 0,
      'routes' => [
        {'vehicle' => resource.id, 'steps' => [
          {'type' => 'start', 'duration' => 0, 'arrival' => 0},
          {'type' => 'pickup', 'id' => pickup.id, 'duration' => 300,
           'arrival' => Time.utc(2026, 8, 3, 9, 0).to_i, 'waiting_time' => 0, 'service' => 600},
          {'type' => 'delivery', 'id' => delivery.id, 'duration' => 900,
           'arrival' => Time.utc(2026, 8, 3, 10, 0).to_i, 'waiting_time' => 0, 'service' => 600}
        ]}
      ],
      'unassigned' => []
    }
    transport, = stub_transport(response)

    Solver.call(run, adapter: Adapter.new(transport: transport))

    kinds = run.reload.scheduler_assignments.order(:sequence).pluck(:issue_id, :kind)
    assert_equal [[pickup.id, 'pickup'], [delivery.id, 'delivery']], kinds
  end

  test 'unassigned shipment stops get diagnosed like jobs' do
    pickup = place(Issue.find(1), 139.70, 35.68)
    delivery = place(Issue.find(2), 139.75, 35.70)
    delivery.update!(start_date: DAY, due_date: DAY,
                     start_time: '18:00', due_time: '19:00')
    pair(pickup, delivery.reload)
    build_resource(@project, work_starts: '08:00', work_ends: '17:00')
    run = build_run(@project, @user, DAY,
                    status: SchedulerRun::PROPOSED,
                    response_payload: {'unassigned' => [
                      {'id' => pickup.id}, {'id' => delivery.id}
                    ]}.to_json)

    report = RedmineGttScheduler::Scheduler::UnassignedReport.call(run)

    # The delivery window is outside every shift; the pickup itself would
    # fit, which the per-stop diagnosis reflects honestly.
    assert_equal :outside_working_hours, report[delivery.id]
    assert_equal :no_room_in_plan, report[pickup.id]
  end
end
