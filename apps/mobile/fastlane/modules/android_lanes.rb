# --- Platform: Android ---

platform :android do
  desc "Build and distribute Android app (interactive)"
  lane :build do |options|
    run_build(platform: :android, options: options)
  end

  desc "Upload existing artifact to store (skip build)"
  lane :upload do |options|
    build_options = options.merge(
      skip_build: true,
      skip_setup: true,
      flutter_version: "stable",
      distribute_store: true,
      distribute_firebase: false
    )
    run_build(platform: :android, options: build_options)
  end

  desc "Build and distribute Android app to Play Store (Prod flavor, AAB)"
  lane :store do |options|
    # Call build lane with store-specific defaults
    build_options = options.merge(
      is_store_lane: true,
      flavor: 'prod',
      build_type: 'aab',
      distribute_store: true,
      distribute_firebase: false
    )
    run_build(platform: :android, options: build_options)
  end
end
