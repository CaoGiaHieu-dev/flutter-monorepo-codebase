# Root Gemfile — lets `bundle install` + `bundle exec fastlane <lane>` run from
# the repository root (what .github/workflows/fastlane.yml does).
#
# Keep the gem list identical to apps/mobile/Gemfile, the one used when running
# from apps/mobile/. Plugins are NOT listed here: they live in exactly one place,
# apps/mobile/fastlane/Pluginfile, which the root fastlane/Pluginfile forwards to.
#
# The `plugins_path` lines are the form fastlane looks for: it treats plugins as
# set up only when the Gemfile it finds loads a Pluginfile. Without them every
# run from the root stops at "It looks like fastlane plugins are not yet set up
# for this project" and asks to rewrite this file — which fails in CI.

source "https://rubygems.org"

gem "fastlane"
gem "cocoapods"

plugins_path = File.join(File.dirname(__FILE__), "fastlane", "Pluginfile")
eval_gemfile(plugins_path) if File.exist?(plugins_path)
