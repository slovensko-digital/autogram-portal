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
  get "/.well-known/autogram-portal.json" => "federation/metadata#show"
  get "federation/requests/open" => "federation/requests#show", as: :federation_requests_open
  post "federation/requests/claim" => "federation/requests#claim", as: :federation_requests_claim

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "sdk.js" => "sdk#sdk", as: :sdk

  post "locale/switch" => "locale#switch", as: :switch_locale
  get "signature-evidence/verify" => "signature_evidence_verifications#show", as: :signature_evidence_verification
  get "signature-evidence/verify/:reference/download" => "signature_evidence_verifications#download", as: :download_signature_evidence_verification
  get "signature-evidence/verify/:reference/download-private" => "signature_evidence_verifications#download_private", as: :download_private_signature_evidence_verification

  # Defines the root path route ("/")
  root to: "root#index"

  resources :about, only: [ :index ]
  resources :docs, only: [ :index ]

  get  "consent" => "consents#new",    as: :new_consent
  post "consent" => "consents#create", as: :consent

  get  "oauth_consent" => "oauth_consents#new",    as: :new_oauth_consent
  post "oauth_consent" => "oauth_consents#create", as: :oauth_consent

  authenticate(:user) do
    get "/dashboard", to: "dashboard#index", as: :dashboard

    resources :contracts, only: [ :index, :destroy ]
    resources :contract_validation_records, only: [ :index, :destroy ] do
      post :refresh, on: :member
    end

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
      get :content_versions
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
      get :visual_signing
      post :visual_signing, action: :create_visual_session
      get :show_bundle
    end

    resources :onboarding, only: [ :show, :update ], param: :step, controller: "contracts/onboarding"
    resources :signature_field_preparations, only: [ :index, :create, :destroy ], controller: "contracts/signature_field_preparations" do
      post :finalize, on: :collection
    end

    resources :sessions, only: [ :show, :destroy ], controller: "contracts/sessions" do
      member do
        get :parameters
        get :download
        post :upload
        post :request_verification
        post :verify_verification
        post :complete_signing
        get :get_webhook
        post :standard_webhook
      end

      get :autogram, on: :collection, to: "contracts/sessions#create", defaults: { type: "autogram" }
      get :ades, on: :collection, to: "contracts/sessions#create", defaults: { type: "ades" }
      get :eidentita, on: :collection, to: "contracts/sessions#create", defaults: { type: "eidentita" }
      get :avm, on: :collection, to: "contracts/sessions#create", defaults: { type: "avm" }
      get :podpisuj, on: :collection, to: "contracts/sessions#create", defaults: { type: "podpisuj" }
    end
  end

  resources :bundles, only: [] do
    member do
      get :sign
      get :autogram_batch
      post :decline
      post :accept
    end
  end

  namespace :api do
    namespace :federation do
      namespace :v1 do
        resources :requests, only: [ :show ], controller: "requests" do
          post :claim, on: :member
        end
      end
    end

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

  authenticate(:user, ->(user) { user.admin? }) do
    namespace :admin do
      resources :portal_instances, except: [ :show, :destroy ] do
        member do
          post :verify
          post :revoke
        end
      end
    end

    mount GoodJob::Engine => "/admin/good_job"
  end

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?
end
