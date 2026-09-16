# --- Combined Flutter Lanes ---

lane :flutter do |options|
  UI.header("Starting Combined Flutter Build")

  # --- 1. Gather Common Inputs ---
  if options.key?(:flavor)
    flavor_input = options[:flavor]
  else
    flavor_prompt = "Enter flavor (#{VALID_FLAVORS.join(', ')}) or press Enter for none"
    flavor_input = get_input(flavor_prompt)
  end

  flavor = flavor_input.to_s.strip
  if flavor == 'none' || flavor.empty?
    flavor = nil
  elsif !VALID_FLAVORS.include?(flavor)
    UI.user_error!("Invalid flavor '#{flavor}'. Valid options are: #{VALID_FLAVORS.join(', ')}.")
  end

  flutter_version = options[:flutter_version] || get_input("Enter the Flutter version", CONFIG.dig('flutter', 'default_version') || 'stable')
  version = options[:version] || get_input("Enter the app version", DEFAULT_APP_VERSION)
  build_number_input = options[:build_number] || get_build_number_input("Enter build number for BOTH platforms ('auto' for auto-increment)", 'auto')
  build_type_android = options[:build_type] || get_validated_input("Build Android to apk or aab?", VALID_BUILD_TYPES, "apk")
  distribute_store = options[:distribute_store].nil? ? get_boolean_input("Distribute to App Store AND Play Store?", false) : options[:distribute_store]
  distribute_firebase = options[:distribute_firebase].nil? ? get_boolean_input("Distribute to Firebase (both platforms)?", !distribute_store) : options[:distribute_firebase]
  track_android = (distribute_store) ? (options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal")) : nil

  # --- 2. Manage Change Log (Once) ---
  change_log = options[:change_log] || get_multiline_input("Enter the change log (used for both platforms)")
  # Save to both files so platform lanes can read it without prompting again
  UI.message("Writing change log to temporary files...")
  File.write(CHANGE_LOG_IOS_FILE, change_log)
  File.write(CHANGE_LOG_ANDROID_FILE, change_log)

  # --- 3. Setup Environment (Once) ---
  setup_flutter_environment(flutter_version, false)

  # --- 4. Run iOS Build ---
  UI.header("Running iOS Build via `sh fastlane ios build`")
  begin
    # Construct the command string for iOS build
    ios_cmd = [
      "fastlane ios build",
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:'#{build_number_input}'", # Quote 'auto' or number
      "flavor:#{flavor}",
      "distribute_store:#{distribute_store}",
      "distribute_firebase:#{distribute_firebase}",
      "skip_setup:true"
      # change_log is read from file by the 'ios build' lane
    ].join(' ')
    UI.message("Executing: #{ios_cmd}")
    sh(ios_cmd)
  rescue => e
    UI.error("iOS build failed: #{e.message}")
    UI.important("Skipping Android build due to iOS failure.")
    raise # Stop the whole process
  end


  # --- 5. Run Android Build ---
  UI.header("Running Android Build via `sh fastlane android build`")
  begin
    # Construct the command string for Android build
    android_cmd_parts = [
      "fastlane android build",
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:'#{build_number_input}'", # Quote 'auto' or number
      "flavor:#{flavor}",
      "build_type:#{build_type_android}",
      "distribute_store:#{distribute_store}",
      "distribute_firebase:#{distribute_firebase}",
      "skip_setup:true"
      # change_log is read from file by the 'android build' lane
    ]
    # Add track only if distributing to store
    android_cmd_parts << "track:#{track_android}" if distribute_store && track_android

    android_cmd = android_cmd_parts.join(' ')
    UI.message("Executing: #{android_cmd}")
    sh(android_cmd)
  rescue => e
    UI.error("Android build failed: #{e.message}")
    raise # Stop the whole process
  end

  UI.success("Combined Flutter build process completed.")
ensure
  # Clean up change log files created by this lane
  UI.message("Cleaning up temporary change log files...")
  File.delete(CHANGE_LOG_IOS_FILE) if File.exist?(CHANGE_LOG_IOS_FILE)
  File.delete(CHANGE_LOG_ANDROID_FILE) if File.exist?(CHANGE_LOG_ANDROID_FILE)
end

lane :store do |options|
  UI.header("Starting Combined Store Release Build (Prod)")

  # --- 1. Gather Common Inputs (Defaults to Prod/Store) ---
  flutter_version = options[:flutter_version] || get_input("Enter the Flutter version", CONFIG.dig('flutter', 'default_version') || 'stable')
  version = options[:version] || get_input("Enter the app version", DEFAULT_APP_VERSION)
  build_number_input = options[:build_number] || get_build_number_input("Enter build number for BOTH platforms ('auto' for auto-increment)", 'auto')
  track_android = options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal")

  # --- 2. Manage Change Log (Once) ---
  change_log = options[:change_log] || get_multiline_input("Enter the change log (used for both platforms)")
  UI.message("Writing change log to temporary files...")
  File.write(CHANGE_LOG_IOS_FILE, change_log)
  File.write(CHANGE_LOG_ANDROID_FILE, change_log)

  # --- 3. Setup Environment (Once) ---
  setup_flutter_environment(flutter_version, false)

  # --- 4. Run iOS Store Build ---
  UI.header("Running iOS Store Build via `sh fastlane ios store`")
  begin
    # Construct the command string for iOS store build
    ios_cmd = [
      "fastlane ios store",
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:'#{build_number_input}'", # Quote 'auto' or number
      "skip_setup:true"
    ].join(' ')
    UI.message("Executing: #{ios_cmd}")
    sh(ios_cmd)
  rescue => e
    UI.error("iOS store build failed: #{e.message}")
    UI.important("Skipping Android store build due to iOS failure.")
    raise
  end

  # --- 5. Run Android Store Build ---
  UI.header("Running Android Store Build via `sh fastlane android store`")
  begin
    # Construct the command string for Android store build
    android_cmd = [
      "fastlane android store",
      "flutter_version:#{flutter_version}",
      "version:#{version}",
      "build_number:'#{build_number_input}'", # Quote 'auto' or number
      "track:#{track_android}",
      "skip_setup:true" # Already set up by iOS lane
      # change_log is read from file by the 'android store' lane
    ].join(' ')
    UI.message("Executing: #{android_cmd}")
    sh(android_cmd)
  rescue => e
    UI.error("Android store build failed: #{e.message}")
    raise
  end

  UI.success("Combined Store release build process completed.")
ensure
  # Clean up change log files
  UI.message("Cleaning up temporary change log files...")
  File.delete(CHANGE_LOG_IOS_FILE) if File.exist?(CHANGE_LOG_IOS_FILE)
  File.delete(CHANGE_LOG_ANDROID_FILE) if File.exist?(CHANGE_LOG_ANDROID_FILE)
end
