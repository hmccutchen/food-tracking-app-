Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resources :patients do
    resources :restrictions, only: %i[create edit update destroy]
  end
  resources :foods, only: :index
  resources :custom_items, path: "custom-items" do
    patch :marks, on: :member
  end
  resource :group, only: :show do
    post :check
  end
  resources :meal_requests, path: "meal-requests", only: %i[create show] do
    post :recheck, on: :member
  end
  namespace :settings do
    resource :ai, only: %i[show update], controller: "ai"
    resources :ai_credentials, path: "ai", param: :provider, only: :update do
      post :test, on: :member
    end
  end
  resources :prep_methods, only: %i[index edit update], path: "preparation-notes"
  resources :ingredient_descriptors, only: %i[index create edit update], path: "descriptor-words"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
