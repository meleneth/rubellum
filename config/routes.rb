Rails.application.routes.draw do
  root "home#index"
  get "/up", to: "health#show"
end
