# frozen_string_literal: true

Rails.application.routes.draw do
  # One endpoint per conversation. The AG-UI client POSTs a RunAgentInput here
  # and reads the event stream back.
  post '/agent', to: 'agent_runs#create'
end
