Rails.application.routes.draw do
  root "home#index"
  get "/up", to: "health#show"
  mount ActionCable.server => "/cable"
  resources :apps, only: [:create, :show, :update] do
    resources :assets, only: [:index, :create, :show]
    resources :notebooks, only: [:create, :show] do
      member do
        get :history
        post :restore
        post :reset
        post :run_all
      end
      resources :cells, only: [:create, :update, :destroy] do
        member do
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
