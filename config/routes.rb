resources :projects, only: [] do
  resources :engagement_contracts, except: [:index] do
    member do
      post 'add_version'
      delete 'remove_version'
      get 'dashboard', to: 'engagement_dashboard#show_authenticated'
      post 'reset_dashboard_link'
    end
    resources :versions, controller: 'engagement_contract_versions', only: [:new, :create, :edit, :update, :destroy]
  end
  get 'engagement_contracts', to: 'engagement_contracts#index', as: 'engagement_contracts_list'
end

post 'engagement_dashboard_logo', to: 'engagement_dashboard#upload_logo'
get 'engagement_dashboard_logo', to: 'engagement_dashboard#serve_logo'

# Public (token-based, no login)
get 'engagement_dashboard/:project_id/:engagement_contract_id/:token', to: 'engagement_dashboard#show', as: 'engagement_dashboard_public'
get 'engagement_dashboard/:project_id/:engagement_contract_id/:token/data', to: 'engagement_dashboard#data', as: 'engagement_dashboard_public_data'
