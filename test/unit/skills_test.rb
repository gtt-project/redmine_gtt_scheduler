require File.expand_path('../test_helper', __dir__)

class SkillsTest < ActiveSupport::TestCase
  include SchedulerTestHelper

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles, :custom_fields, :custom_values

  Builder = RedmineGttScheduler::Scheduler::ProblemBuilder
  Report = RedmineGttScheduler::Scheduler::UnassignedReport

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @day = Date.new(2026, 8, 3)
    enable_scheduler(@project)
    @factory = RGeo::Geographic.spherical_factory(srid: 4326)
    # Dates cleared too: fixture dates are relative to today and would push
    # issues outside the fixed planning day at some point (#22).
    Issue.where(project_id: @project.id)
         .update_all(geom: nil, start_date: nil, due_date: nil)
    @issue = Issue.find(1)
    @issue.update_columns(geom: @factory.point(139.7, 35.68).to_s)
  end

  # The vocabulary is a list-format issue custom field picked in the
  # plugin settings; its id is stored, never its name.
  def create_skills_field(values = %w[electric plumbing])
    field = IssueCustomField.create!(
      name: 'Required skills', field_format: 'list', multiple: true,
      possible_values: values, is_for_all: true,
      tracker_ids: Tracker.pluck(:id)
    )
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('skills_custom_field_id' => field.id.to_s)
    field
  end

  def require_skills(issue, field, values)
    issue.custom_field_values = {field.id.to_s => values}
    issue.save!
    issue.reload
  end

  test 'job and vehicle skills share one id space per problem' do
    field = create_skills_field
    require_skills(@issue, field, ['electric'])
    build_resource(@project, skills: %w[electric plumbing])

    problem = Builder.new(build_run(@project, @user, @day)).build

    job = problem.jobs.first
    vehicle = problem.vehicles.first
    # Sorted names, 1-based: electric => 1, plumbing => 2.
    assert_equal [1], job.skills
    assert_equal [1, 2], vehicle.skills
  end

  test 'without a configured custom field no skills are emitted' do
    build_resource(@project, skills: ['electric'])

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_nil problem.jobs.first.skills
    assert_nil problem.vehicles.first.skills
  end

  test 'an issue without skill values can go to any resource' do
    create_skills_field
    build_resource(@project, skills: ['electric'])

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_nil problem.jobs.first.skills
    assert_equal [1], problem.vehicles.first.skills
  end

  # A value removed from the vocabulary can still be stored on issues and
  # resources; the per-problem union map keeps it matching.
  test 'a skill name outside the current vocabulary still matches' do
    field = create_skills_field(%w[electric])
    require_skills(@issue, field, ['electric'])
    # Simulates a stored value that the admin later removed from the field.
    @issue.custom_values.where(custom_field_id: field.id).first.update_column(:value, 'legacy')
    build_resource(@project, skills: ['legacy'])

    problem = Builder.new(build_run(@project, @user, @day)).build

    assert_equal problem.jobs.first.skills, problem.vehicles.first.skills
  end

  test 'the request carries skills only when present' do
    field = create_skills_field
    require_skills(@issue, field, ['plumbing'])
    build_resource(@project, skills: [])
    problem = Builder.new(build_run(@project, @user, @day)).build

    request = RedmineGttScheduler::Scheduler::VroomExpressAdapter.new(transport: ->(_) { '{}' })
                                                                 .build_request(problem)

    assert_equal [1], request['jobs'].first['skills']
    assert_not request['vehicles'].first.key?('skills'),
               'a vehicle without skills must omit the key'
  end

  test 'a job whose skills no resource offers is diagnosed as such' do
    field = create_skills_field
    require_skills(@issue, field, ['plumbing'])
    build_resource(@project, skills: ['electric'])
    run = build_run(@project, @user, @day,
                    status: SchedulerRun::PROPOSED,
                    response_payload: {'unassigned' => [{'id' => @issue.id}]}.to_json)

    assert_equal Report::MISSING_SKILLS, Report.call(run)[@issue.id]
  end

  # The window analysis must only look at resources that could serve the
  # job at all, or the reason would point at the wrong resource's shift.
  test 'window diagnostics only consider resources with the skills' do
    field = create_skills_field
    require_skills(@issue, field, ['electric'])
    @issue.update!(start_date: @day, due_date: @day,
                   start_time: '14:00', due_time: '15:00')
    # Has the skill, but works mornings only.
    build_resource(@project, name: 'Electrician',
                             skills: ['electric'], work_starts: '08:00', work_ends: '12:00')
    # Works the right hours, but cannot serve the job.
    build_resource(@project, name: 'Plumber',
                             skills: ['plumbing'], work_starts: '08:00', work_ends: '17:00')
    run = build_run(@project, @user, @day,
                    status: SchedulerRun::PROPOSED,
                    response_payload: {'unassigned' => [{'id' => @issue.id}]}.to_json)

    assert_equal Report::OUTSIDE_WORKING_HOURS, Report.call(run)[@issue.id]
  end

  test 'the skills writer drops blanks from the form submission' do
    resource = build_resource(@project, skills: ['', 'electric', ''])

    assert_equal ['electric'], resource.reload.skills
  end
end
