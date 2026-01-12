Rails.application.routes.draw do
  devise_for :users,
    controllers: {
      sessions: "users/sessions",
      registrations: "users/registrations",
      confirmations: "users/confirmations",
      omniauth_callbacks: "users/omniauth"
    }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Chrome DevTools configuration for better debugging experience
  get "/.well-known/appspecific/com.chrome.devtools.json" => "application#devtools_config"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "sdk.js" => "sdk#sdk", as: :sdk

  post "locale/switch" => "locale#switch", as: :switch_locale

  # Defines the root path route ("/")
  root to: "homepage#index"

  resources :privacy_policy, only: [ :index ]
  resources :terms_of_service, only: [ :index ]

  authenticate(:user) do
    resources :contracts, only: [ :index, :destroy, :edit, :update ]
    resources :documents, only: [ :index ] do
      member do
        post :extend_signatures
      end
    end
    resources :bundles, only: [ :index, :edit, :update, :destroy ]
  end

  resources :documents, only: [ :new, :create, :show ] do
    member do
      get :validate
      get :visualize
      get :pdf_preview
      get :actions
      get :download
      post :create_contract_from_document, as: "create_contract_from_document"
    end
  end

  resources :contracts, only: [ :show ] do
    member do
      post :sign
      post :sign_avm
      get :validate
      get :visualize
      get :signed_document
      get :iframe
      get :autogram_parameters
      get :autogram_signing_in_progress
    end
  end

  resources :bundles, only: [ :show ] do
    member do
      get :iframe
    end
  end

  namespace :api do
    namespace :v1 do
      get "hello", to: "hello#show"
      get "hello_auth", to: "hello#show_auth"

      resources :contracts, only: [ :create, :show, :destroy ] do
        member do
          get :signed_document
          get :status
        end
      end

      resources :documents, only: [ :show ]

      resources :bundles, only: [ :create, :show, :destroy ] do
        member do
          get :status
        end
      end
    end
  end

  # add good job admin interface at /admin/good_job
  mount GoodJob::Engine => "/admin/good_job"
end
