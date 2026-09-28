Rails.application.routes.draw do
  root "home#index"
  get "/up", to: "health#show"
  mount ActionCable.server => "/cable"
  get "/apps/import", to: "app_packages#new", as: :import_apps
  post "/apps/import", to: "app_packages#create"
  resources :apps, only: [:create, :show, :update] do
    get :history, on: :member
    post :restore, on: :member
    get :export, on: :member, to: "app_packages#export"
    post :duplicate, on: :member, to: "app_packages#duplicate"
    resources :assets, only: [:index, :create, :show]
    resources :notebooks, only: [:create, :show, :update] do
      member do
        get :history
        post :restore
        post :reset
        post :run_all
      end
      resources :cells, only: [:create, :update, :destroy] do
        post :import_file, on: :collection
        member do
          get :export
          post :run
          post :move
          post :restore
          get :output
          get :history
          get :data
          get :draft
          put :draft, action: :save_draft
          patch :parameters
        end
      end
      resources :executions, only: [] do
        post :interrupt, on: :member
      end
    end
  end
  get "/renderer", to: "home#renderer"
end
