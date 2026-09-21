# --- Platform: iOS ---

platform :ios do
  before_all do
  end

  desc "Build and distribute iOS app (interactive)"
  lane :build do |options|
    run_build(platform: :ios, options: options)
  end

  desc "Upload existing IPA to store (skip build)"
  lane :upload do |options|
    build_options = options.merge(
      skip_build: true,
      skip_setup: true,
      flutter_version: "stable",
      distribute_store: true,
      distribute_firebase: false
    )
    run_build(platform: :ios, options: build_options)
  end

  desc "Build and distribute iOS app to TestFlight (Prod flavor)"
  lane :store do |options|
    # Call build lane with store-specific defaults
    build_options = options.merge(
      is_store_lane: true,
      flavor: 'prod',
      distribute_store: true,
      distribute_firebase: false
    )
    run_build(platform: :ios, options: build_options)
  end
end
