Redmine::Plugin.register :redmine_project_engagement do
  name 'Redmine Project Engagement'
  author 'LS MARK'
  description 'Manage project Engagement Contracts, version tracking, and project dashboard.'
  version '1.1.0'
  url 'https://daxonet.com'
  author_url 'https://daxonet.com/about'

  requires_redmine version_or_higher: '6.0'

  settings default: {
    'customization_tracker_id' => '',
    'customization_subtask_tracker_id' => '',
    'stage_field_id'           => '',
    'stage_subtask_list'       => 'Design,Develop,Testing'
  }, partial: 'settings/redmine_project_engagement'

  project_module :project_engagement do
    permission :view_engagement_contracts, {
      engagement_contracts: [:index, :show]
    }, read: true
    permission :view_engagement_dashboard, {
      engagement_dashboard: [:show_authenticated]
    }, read: true
    permission :share_engagement_dashboard, {
      engagement_contracts: [:reset_dashboard_link]
    }
    permission :manage_engagement_contracts, {
      engagement_contracts: [:new, :create, :edit, :update, :destroy, :add_version, :remove_version]
    }
    permission :manage_engagement_contract_versions, {
      engagement_contract_versions: [:new, :create, :edit, :update, :destroy]
    }
  end

  menu :project_menu, :engagement_contracts,
       { controller: 'engagement_contracts', action: 'index' },
       caption: :label_engagement_contracts,
       after: :activity,
       param: :project_id
end

Rails.configuration.to_prepare do
  require_dependency 'redmine_project_engagement/version_patch'
  require_dependency 'redmine_project_engagement/project_patch'
  require_dependency 'redmine_project_engagement/issue_patch'
end
