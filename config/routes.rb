Rails.application.routes.draw do
  devise_for :users,
    controllers: {
      sessions: "users/sessions",
      registrations: "users/registrations",
      confirmations: "users/confirmations",
      unlocks: "users/unlocks",
      omniauth_callbacks: "users/omniauth"
    }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  get "altcha/challenge" => "altcha#challenge", as: :altcha_challenge

  # Chrome DevTools configuration for better debugging experience
  get "/.well-known/appspecific/com.chrome.devtools.json" => "application#devtools_config"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "sdk.js" => "sdk#sdk", as: :sdk

  post "locale/switch" => "locale#switch", as: :switch_locale

  # Defines the root path route ("/")
  root to: "root#index"

  resources :privacy_policy, only: [ :index ]
  resources :terms_of_service, only: [ :index ]
  resources :about, only: [ :index ]
  resources :docs, only: [ :index ]

  authenticate(:user) do
    get "/dashboard", to: "dashboard#index", as: :dashboard

    resources :contracts, only: [ :index, :destroy ]

    resources :bundles, only: [ :index, :show, :edit, :update, :destroy ] do
      collection do
        get :received
      end
      resources :recipients, only: [ :create, :index, :destroy ] do
        member do
          post :notify
        end
      end
    end
  end

  resources :documents, only: [] do
    member do
      get :visualize
      get :pdf_preview
      get :download
    end
  end

  resources :contracts, except: [ :index ] do
    member do
      get :signature_apps
      get :sign
      get :validate
      get :visualize
      get :signed_document
      get :signature_parameters
      get :signature_extension
      post :extend_signatures
      get :actions
      get :signature_apps
      get :physical_signing
      post :physical_signing, action: :create_physical_session
    end

    resources :onboarding, only: [ :show, :update ], param: :step, controller: "contracts/onboarding"

    resources :sessions, only: [ :show, :destroy ], controller: "contracts/sessions" do
      member do
        get :parameters
        get :download
        post :upload
        get :get_webhook
        post :standard_webhook
      end

      get :autogram, on: :collection, to: "contracts/sessions#create", defaults: { type: "autogram" }
      get :eidentita, on: :collection, to: "contracts/sessions#create", defaults: { type: "eidentita" }
      get :avm, on: :collection, to: "contracts/sessions#create", defaults: { type: "avm" }
    end
  end

  resources :bundles, only: [] do
    member do
      get :sign
      post :decline
      post :accept
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

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end
