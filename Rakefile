# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"
require "rubocop/rake_task"

Minitest::TestTask.create(:test) do |t|
  t.test_globs = ["test/*_test.rb", "test/gigachat/**/*_test.rb"]
end

namespace :test do
  Minitest::TestTask.create(:live) do |t|
    t.test_globs = ["test/live/**/*_test.rb"]
  end
end

RuboCop::RakeTask.new

task default: %i[test rubocop]
