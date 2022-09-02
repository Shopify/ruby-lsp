Rails.application.routes.draw do
  concern :snapshotable do
    resources :snapshots, only: [:index, :show]
  end

  root "projects#index"

  mount Sidekiq::Web => "/sidekiq"
end

# ignore

before_save :foo
before_action :bar
