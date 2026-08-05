require_relative 'lib/redmine_gtt_scheduler'

Redmine::Plugin.register :redmine_gtt_scheduler do
  name 'Redmine GTT Scheduler'
  author 'GTT Project'
  description 'VRP-based schedule optimization for location-based issues'
  version '0.1.0'
  url 'https://github.com/gtt-project/redmine_gtt_scheduler'
  author_url 'https://github.com/gtt-project'

  requires_redmine version_or_higher: '6.0'
  requires_redmine_plugin :redmine_gtt, version_or_higher: '7.0.0'

  settings partial: 'settings/redmine_gtt_scheduler',
           default: {
             # Deliberately not localhost:3000: that is Redmine's own port in
             # most setups, so an unconfigured scheduler would post to Redmine.
             'vroom_url' => 'http://vroom:3000',
             'default_service_minutes' => '30',
             'solver_timeout' => '60',
             'request_geometry' => '1',
             # Empty = skills matching off.
             'skills_custom_field_id' => ''
           }

  project_module :gtt_scheduler do
    permission :view_scheduler,
               {scheduler_runs: [:index, :show]},
               read: true
    permission :manage_scheduler,
               {
                 scheduler_runs: [:new, :create, :apply, :discard],
                 scheduler_resources: [:index, :new, :create, :edit, :update, :destroy]
               },
               require: :member
  end

  menu :project_menu, :gtt_scheduler,
       {controller: 'scheduler_runs', action: 'index'},
       param: :project_id,
       caption: :label_scheduler
end

RedmineGttScheduler.setup

# redmine_issue_datetime sorts after this plugin in the load order, so
# requires_redmine_plugin cannot see it during registration.
Rails.application.config.after_initialize do
  unless Redmine::Plugin.installed?(:redmine_issue_datetime)
    Rails.logger.error(
      'redmine_gtt_scheduler requires the redmine_issue_datetime plugin ' \
      '(https://github.com/gtt-project/redmine_issue_datetime)'
    )
  end
end
