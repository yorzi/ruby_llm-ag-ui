# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Run store contract' do
  context 'with memory storage' do
    let(:store) { RubyLLM::AgUI::Store::MemoryStore.new }

    it_behaves_like 'versioned run storage'
  end

  context 'with durable storage' do
    let(:store) { RubyLLM::AgUI::Rails::ActiveRecordStore.new }

    it_behaves_like 'versioned run storage'
  end
end
