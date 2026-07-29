require File.expand_path('../test_helper', __dir__)

class SchedulerSettingsTest < Redmine::ControllerTest
  tests SettingsController

  fixtures :projects, :users, :email_addresses, :roles, :trackers,
           :projects_trackers, :enabled_modules

  def setup
    @request.session[:user_id] = 1
  end

  test 'the plugin settings page renders' do
    get :plugin, params: {id: 'redmine_gtt_scheduler'}

    assert_response :success
    assert_select 'input[name=?]', 'settings[vroom_url]'
    assert_select 'input[name=?]', 'settings[default_service_minutes]'
    assert_select 'input[name=?]', 'settings[solver_timeout]'
  end

  # Redmine itself usually occupies port 3000, so the default must not be
  # localhost:3000 or an unconfigured scheduler would post to Redmine.
  test 'the default solver URL does not point at Redmine itself' do
    Setting.plugin_redmine_gtt_scheduler = {}

    assert_equal 'http://vroom:3000', RedmineGttScheduler.vroom_url
  end

  test 'saving the plugin settings works' do
    post :plugin, params: {
      id: 'redmine_gtt_scheduler',
      settings: {'vroom_url' => 'http://vroom:3000', 'default_service_minutes' => '45',
                 'solver_timeout' => '90'}
    }

    assert_redirected_to controller: 'settings', action: 'plugin', id: 'redmine_gtt_scheduler'
    assert_equal 'http://vroom:3000', RedmineGttScheduler.vroom_url
    assert_equal 2700, RedmineGttScheduler.default_service_seconds
  end
end
