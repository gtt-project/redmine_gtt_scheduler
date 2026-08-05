require File.expand_path('../test_helper', __dir__)

class SchedulerResourcesControllerTest < Redmine::ControllerTest
  include SchedulerTestHelper

  tests SchedulerResourcesController

  fixtures :projects, :users, :email_addresses, :trackers, :projects_trackers,
           :issue_statuses, :issues, :enumerations, :enabled_modules,
           :members, :member_roles, :roles

  def setup
    @project = Project.find(1)
    enable_scheduler(@project)
    Role.find(1).add_permission!(:view_scheduler, :manage_scheduler)
    @request.session[:user_id] = 2
  end

  test 'index lists the resources' do
    resource = build_resource(@project)

    get :index, params: {project_id: @project.identifier}

    assert_response :success
    assert_select 'td', text: resource.name
    assert_select 'a[data-method=?]', 'delete'
  end

  test 'create adds a resource' do
    assert_difference 'SchedulerResource.count' do
      post :create, params: {
        project_id: @project.identifier,
        scheduler_resource: {
          name: 'Crew B', start_lng: '139.70', start_lat: '35.68',
          work_starts: '08:00', work_ends: '17:00', active: '1'
        }
      }
    end

    assert_redirected_to "/projects/#{@project.identifier}/scheduler_resources"
    assert_equal 'Crew B', SchedulerResource.last.name
  end

  test 'create rejects working hours in the wrong order' do
    assert_no_difference 'SchedulerResource.count' do
      post :create, params: {
        project_id: @project.identifier,
        scheduler_resource: {
          name: 'Crew C', start_lng: '139.70', start_lat: '35.68',
          work_starts: '17:00', work_ends: '08:00'
        }
      }
    end

    assert_response :success
    assert_select '#errorExplanation'
  end

  test 'update changes a resource' do
    resource = build_resource(@project)

    patch :update, params: {
      project_id: @project.identifier, id: resource.id,
      scheduler_resource: {name: 'Renamed'}
    }

    assert_redirected_to "/projects/#{@project.identifier}/scheduler_resources"
    assert_equal 'Renamed', resource.reload.name
  end

  test 'destroy removes a resource without assignments' do
    resource = build_resource(@project)

    assert_difference 'SchedulerResource.count', -1 do
      delete :destroy, params: {project_id: @project.identifier, id: resource.id}
    end
  end

  test 'a resource used by a run cannot be destroyed' do
    resource = build_resource(@project)
    run = build_run(@project, User.find(2), Date.new(2026, 8, 3), status: SchedulerRun::PROPOSED)
    run.scheduler_assignments.create!(
      issue: Issue.find(1), scheduler_resource: resource, sequence: 1,
      starts_at: Time.utc(2026, 8, 3, 9, 0), ends_at: Time.utc(2026, 8, 3, 10, 0)
    )

    assert_no_difference 'SchedulerResource.count' do
      delete :destroy, params: {project_id: @project.identifier, id: resource.id}
    end
    assert_nil flash[:notice]
    assert flash[:error].present?
  end

  test 'create stores the selected skills' do
    field = IssueCustomField.create!(
      name: 'Required skills', field_format: 'list', multiple: true,
      possible_values: %w[electric plumbing], is_for_all: true,
      tracker_ids: Tracker.pluck(:id)
    )
    Setting.plugin_redmine_gtt_scheduler =
      Setting.plugin_redmine_gtt_scheduler.merge('skills_custom_field_id' => field.id.to_s)

    post :create, params: {
      project_id: @project.identifier,
      scheduler_resource: {
        name: 'Crew E', start_lng: '139.70', start_lat: '35.68',
        work_starts: '08:00', work_ends: '17:00', skills: ['', 'electric']
      }
    }

    assert_equal ['electric'], SchedulerResource.last.skills
  end

  test 'single-digit working hours are accepted' do
    assert_difference 'SchedulerResource.count' do
      post :create, params: {
        project_id: @project.identifier,
        scheduler_resource: {
          name: 'Crew D', start_lng: '139.70', start_lat: '35.68',
          work_starts: '8:00', work_ends: '17:00'
        }
      }
    end
  end
end
