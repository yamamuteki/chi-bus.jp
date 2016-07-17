Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :bus_routes, only: [:show]
  resources :bus_stops, only: [:index, :show]
  get 'about', to: 'about#index'
  root 'home#index'
end
