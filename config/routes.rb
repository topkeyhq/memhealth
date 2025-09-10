MemHealth::Engine.routes.draw do
  root "dashboard#index"
  post "/clear", to: "dashboard#clear", as: :clear
end
