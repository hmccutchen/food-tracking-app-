Rails.application.routes.draw do
  # Sign-in and sign-out only. There is no sign-up, and no reset email: the
  # nurse account comes from db/seeds.rb (see NURSE_PASSWORD there).
  devise_for :users, controllers: { sessions: "users/sessions" }
  resource :account, only: %i[edit update]
  resources :patients do
    resources :restrictions, only: %i[create edit update destroy]
    # /patients/:id/choose/allergy/edit: pick many items of one kind at once.
    resources :restriction_selections, path: "choose", param: :kind, only: %i[edit update]
  end
  resources :foods, only: :index
  resources :custom_items, path: "custom-items" do
    patch :marks, on: :member
  end
  resource :group, only: :show do
    post :check
  end
  resources :meal_requests, path: "meal-requests", only: %i[index create show destroy] do
    post :recheck, on: :member
    delete :clear, on: :collection
  end
  namespace :settings do
    resource :ai, only: %i[show update], controller: "ai"
    resource :offline, only: %i[show update], controller: "offline"
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

  # PWA files from app/views/pwa/*. Public, and free of patient data.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "home#index"
end
