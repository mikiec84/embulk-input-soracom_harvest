require "bundler/gem_tasks"
require "gem_release_helper/tasks"

task default: :test

desc "Run tests"
task :test do
  # TODO
  #ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

desc "Run tests with coverage"
task :cov do
  ENV["COVERAGE"] = "1"
  ruby("--debug", "test/run-test.rb", "--use-color=yes", "--collector=dir")
end

GemReleaseHelper::Tasks.install({
  gemspec: "./embulk-input-soracom_harvest.gemspec",
  github_name: "sakama/embulk-input-soracom_harvest",
})