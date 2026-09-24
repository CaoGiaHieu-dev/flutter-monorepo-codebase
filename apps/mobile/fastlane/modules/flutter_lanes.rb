# --- Combined Flutter Lanes ---
#
# Both lanes gather their inputs once, set the toolchain up once, then run the
# iOS lane and the Android lane as child fastlane processes (iOS first; an iOS
# failure stops the run). The change log reaches the children through a temp
# file OUTSIDE the repository whose path is passed explicitly as
# `change_log_file:` — a child never picks up a file it was not told about —
# and the file is deleted in `ensure`, whether the run succeeded or not.

desc "Build both platforms (iOS, then Android) with one set of inputs. Needs macOS"
lane :flutter do |options|
  change_log_file = nil
  begin
    UI.header("Starting Combined Flutter Build")

    # iOS runs first, so off macOS the lane could only fail after setup.
    ensure_ios_host!("flutter")

    # --- 1. Gather Common Inputs ---
    flavor = resolve_flavor(options)

    flutter_version = options[:flutter_version] || get_input("Enter the Flutter version", CONFIG.dig('flutter', 'default_version') || 'stable', option: 'flutter_version')
    version = normalize_version_input(options[:version] || get_input("Enter the app version", DEFAULT_APP_VERSION, option: 'version'))
    build_number_input = options.key?(:build_number) ? options[:build_number] : get_build_number_input("Enter build number for BOTH platforms ('auto' for auto-increment)", 'auto')
    build_number_input = normalize_build_number_input(build_number_input) # fail fast, before any build
    build_type_android = options[:build_type] ? validate_choice(options[:build_type], VALID_BUILD_TYPES, 'build_type') : get_validated_input("Build Android to apk or aab?", VALID_BUILD_TYPES, "apk", option: 'build_type')
    distribute_store = options[:distribute_store].nil? ? get_boolean_input("Distribute to App Store AND Play Store?", false, option: 'distribute_store') : options[:distribute_store]
    distribute_firebase = options[:distribute_firebase].nil? ? get_boolean_input("Distribute to Firebase (both platforms)?", !distribute_store, option: 'distribute_firebase', non_interactive: false) : options[:distribute_firebase]
    track_android = (distribute_store) ? (options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal", option: 'track')) : nil
    skip_setup = options[:skip_setup] == true

    # --- 2. Change Log (Once) ---
    change_log = resolve_change_log(options[:change_log], nil)
    change_log_file = write_temp_change_log(change_log)

    # --- 3. Setup Environment (Once) ---
    setup_flutter_environment(flutter_version, skip_setup, platforms: [:ios, :android], upgrade: options[:flutter_upgrade] == true)

    common_args = [
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:#{build_number_input}",
      "flavor:#{flavor || 'none'}",
      "distribute_store:#{distribute_store}",
      "distribute_firebase:#{distribute_firebase}",
      "change_log_file:#{change_log_file}",
      "skip_setup:true"
    ]

    # --- 4. Run iOS Build ---
    UI.header("Running iOS Build via `fastlane ios build`")
    begin
      run_child_lane("ios", "build", *common_args)
    rescue => e
      UI.error("iOS build failed: #{e.message}")
      UI.important("Skipping Android build due to iOS failure.")
      raise # Stop the whole process
    end

    # --- 5. Run Android Build ---
    UI.header("Running Android Build via `fastlane android build`")
    begin
      android_args = common_args + ["build_type:#{build_type_android}"]
      android_args << "track:#{track_android}" if distribute_store && track_android
      run_child_lane("android", "build", *android_args)
    rescue => e
      UI.error("Android build failed: #{e.message}")
      raise # Stop the whole process
    end

    UI.success("Combined Flutter build process completed.")
  ensure
    FileUtils.rm_rf(File.dirname(change_log_file)) if change_log_file
  end
end

desc "Prod release of both platforms to TestFlight and Google Play. Needs macOS"
lane :store do |options|
  change_log_file = nil
  begin
    UI.header("Starting Combined Store Release Build (Prod)")

    ensure_ios_host!("store")

    # --- 1. Gather Common Inputs (Defaults to Prod/Store) ---
    flutter_version = options[:flutter_version] || get_input("Enter the Flutter version", CONFIG.dig('flutter', 'default_version') || 'stable', option: 'flutter_version')
    version = normalize_version_input(options[:version] || get_input("Enter the app version", DEFAULT_APP_VERSION, option: 'version'))
    build_number_input = options.key?(:build_number) ? options[:build_number] : get_build_number_input("Enter build number for BOTH platforms ('auto' for auto-increment)", 'auto')
    build_number_input = normalize_build_number_input(build_number_input) # fail fast, before any build
    track_android = options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal", option: 'track')
    skip_setup = options[:skip_setup] == true

    # --- 2. Change Log (Once) ---
    change_log = resolve_change_log(options[:change_log], nil)
    change_log_file = write_temp_change_log(change_log)

    # --- 3. Setup Environment (Once) ---
    setup_flutter_environment(flutter_version, skip_setup, platforms: [:ios, :android], upgrade: options[:flutter_upgrade] == true)

    common_args = [
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:#{build_number_input}",
      "change_log_file:#{change_log_file}",
      "skip_setup:true"
    ]

    # --- 4. Run iOS Store Build ---
    UI.header("Running iOS Store Build via `fastlane ios store`")
    begin
      run_child_lane("ios", "store", *common_args)
    rescue => e
      UI.error("iOS store build failed: #{e.message}")
      UI.important("Skipping Android store build due to iOS failure.")
      raise
    end

    # --- 5. Run Android Store Build ---
    UI.header("Running Android Store Build via `fastlane android store`")
    begin
      run_child_lane("android", "store", *common_args, "track:#{track_android}")
    rescue => e
      UI.error("Android store build failed: #{e.message}")
      raise
    end

    UI.success("Combined Store release build process completed.")
  ensure
    FileUtils.rm_rf(File.dirname(change_log_file)) if change_log_file
  end
end
