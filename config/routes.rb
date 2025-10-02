Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Chrome DevTools configuration for better debugging experience
  get "/.well-known/appspecific/com.chrome.devtools.json" => "application#devtools_config"

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root to: "homepage#index"

  resources :documents, only: [ :index, :new, :create, :show ] do
    member do
      get :validate
      get :visualize
      get :pdf_preview
      post 'create_contract_from_document', as: 'create_contract_from_document'
    end
  end

  resources :contracts, only: [ :index, :new, :create, :show, :destroy, :edit ] do
    member do
      post :sign
      post :sign_avm
      get :validate
      get :visualize
      get :signed_document
      get :iframe
    end
  end

  resources :bundles

  # add good job admin interface at /admin/good_job
  mount GoodJob::Engine => "/admin/good_job"
end
