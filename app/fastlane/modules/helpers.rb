# --- Configuration ---
require 'yaml'
require 'timeout'
require 'pathname'

# Get the absolute paths dynamically based on this file's location to support execution from any directory
CONFIG_FILE = File.expand_path("../Config.yaml", __dir__)
APP_DIR = File.expand_path("../..", __dir__)

UI.user_error!("Configuration file not found at #{CONFIG_FILE}") unless File.exist?(CONFIG_FILE)
CONFIG = YAML.load_file(CONFIG_FILE)

# Default App Version (now loaded from YAML)
DEFAULT_APP_VERSION = CONFIG.dig('default_app_version')

# Credentials and paths are now loaded from Config.yaml
FIREBASE_TESTERS_FILE = CONFIG.dig('paths', 'firebase_testers_file')
GOOGLE_PLAY_KEY_PROD = CONFIG.dig('paths', 'google_play_key_prod')
GOOGLE_PLAY_KEY_DEV = CONFIG.dig('paths', 'google_play_key_dev')
APP_STORE_CONNECT_KEY_FILEPATH = CONFIG.dig('paths', 'app_store_connect_key_filepath')
APP_STORE_CONNECT_APPLE_IDS = CONFIG.dig('app_store_connect', 'apple_ids')

# App Store Credentials (now loaded from YAML)
APP_STORE_CONNECT_API_KEY_ID = CONFIG.dig('app_store_connect', 'api_key_id') || ""
APP_STORE_CONNECT_ISSUER_ID = CONFIG.dig('app_store_connect', 'issuer_id') || ""
APP_STORE_USERNAME = CONFIG.dig('app_store_connect', 'username') || ""
APP_STORE_TEAM_ID = CONFIG.dig('app_store_connect', 'team_id') || ""

# Temporary file names for change logs
CHANGE_LOG_ANDROID_FILE = CONFIG.dig('paths', 'change_log_android')
CHANGE_LOG_IOS_FILE = CONFIG.dig('paths', 'change_log_ios')

# Valid options
VALID_FLAVORS = (CONFIG.dig('valid_flavors') || []) + ['none']
VALID_TRACKS = ['production', 'internal', 'closed']
VALID_BUILD_TYPES = ['apk', 'aab']

# --- Helper Functions ---

# Get bundle ID with suffix based on flavor
def get_bundle_id_with_suffix(base_bundle_id, flavor)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then "#{base_bundle_id}.stg"
  else base_bundle_id
  end
end

# Get dart define file path based on flavor
def get_dart_define_file(flavor)
  case flavor
  when 'dev' then "env.dev"
  when 'staging' then "env.stg"
  else "env.prod"
  end
end

# Get user input with a default value
def get_input(prompt_text, default_value = nil)
  prompt = default_value.nil? ? "#{prompt_text}: " : "#{prompt_text} (default: #{default_value}): "
  input = UI.input(prompt)
  input.empty? ? default_value : input.strip
end

# Get build number input with 'auto' option
def get_build_number_input(prompt_text, default_value = nil)
  input = get_input(prompt_text, default_value)
  return default_value if input.nil?
  input.downcase == 'auto' ? 'auto' : input # Return 'auto' string for easier checking
end

# Get boolean user input with a default value
def get_boolean_input(prompt_text, default_value)
  input = UI.input("#{prompt_text} (y/n, default: #{default_value ? 'y' : 'n'}): ").strip.downcase
  return default_value if input.empty?
  return true if ['y', 'yes', 'true'].include?(input)
  return false if ['n', 'no', 'false'].include?(input)
  UI.user_error!("Invalid input. Please enter 'y' or 'n'.")
end

# Get multiline user input
def get_multiline_input(prompt_text, end_keyword = "END")
  UI.important("#{prompt_text} (end with '#{end_keyword}' on a new line):")
  UI.important("--------------------------------------------------")
  input_lines = []
  loop do
    line = UI.input("")
    break if line.strip.casecmp(end_keyword) == 0
    input_lines << line
  end
  input_lines.join("\n").strip
end

# Get flavor input with validation
def get_validated_input(prompt_text, valid_options, default_value)
  input = get_input("#{prompt_text} (#{valid_options.join(', ')}, default: #{default_value})", default_value)
  input_lower = input.downcase
  unless valid_options.include?(input_lower)
    UI.user_error!("Invalid input '#{input}'. Please enter one of the following: #{valid_options.join(', ')}.")
  end
  input_lower
end

# Helper to get Firebase App ID based on platform and flavor
def get_firebase_app_id(platform, flavor)
  actual_flavor_key = (flavor && !flavor.empty?) ? flavor : 'default'
  app_id = CONFIG.dig('firebase', 'app_ids', platform.to_s, actual_flavor_key)
  UI.user_error!("Firebase App ID for platform '#{platform}' and flavor '#{actual_flavor_key}' not set in #{CONFIG_FILE}.") unless app_id
  app_id
end

# Helper to get Firebase credential file path based on flavor
def get_firebase_credential_file(flavor)
  actual_flavor_key = (flavor && !flavor.empty?) ? flavor : 'default'
  credential_file = CONFIG.dig('firebase', 'credentials_map', actual_flavor_key)
  UI.user_error!("Firebase credential file path for flavor '#{actual_flavor_key}' not set in #{CONFIG_FILE}.") unless credential_file
  credential_file
end

# Install project dependencies
def install_dependencies(flutter_version)
  prefix = flutter_version == 'stable' ? "" : "fvm "
  Dir.chdir(APP_DIR) do
    UI.header("Installing Dependencies")
    sh "#{prefix}dart pub global activate flutterfire_cli"
    sh "#{prefix}dart pub global activate flutter_gen"
    sh "#{prefix}flutter clean"
    sh "#{prefix}flutter pub get"

    # Workspace root is one level above APP_DIR
    workspace_root = File.expand_path("..", APP_DIR)

    # Conditionally run 'flutter gen-l10n' for all features
    UI.message("Scanning for l10n.yaml files in workspace to run 'flutter gen-l10n'...")
    l10n_files = Dir.glob(File.join(workspace_root, "packages", "**", "l10n.yaml"))
    
    if l10n_files.empty?
      UI.message("No l10n.yaml found in workspace, skipping 'flutter gen-l10n'.")
    else
      l10n_files.each do |l10n_file|
        pkg_dir = File.dirname(l10n_file)
        UI.message("Found l10n.yaml in #{pkg_dir}. Running 'flutter gen-l10n'...")
        Dir.chdir(pkg_dir) do
          sh "#{prefix}flutter gen-l10n"
        end
      end
    end

    # Run 'build_runner' for the entire workspace
    UI.message("Running build_runner for workspace...")
    Dir.chdir(workspace_root) do
      sh "#{prefix}dart run build_runner build -d --workspace"
    end
  end
end

# Setup Flutter environment (version and dependencies)
def setup_flutter_environment(flutter_version, skip_setup)
  return if skip_setup
  UI.header("Setting up Flutter Environment (Version: #{flutter_version})")
  if flutter_version == "stable"
    sh "flutter channel stable"
    sh "flutter upgrade --force"
    sh "flutter precache --ios"
  else
    Dir.chdir(APP_DIR) do
      UI.header("Activate fvm")
      sh "dart pub global activate fvm"
      sh "fvm install #{flutter_version}"
      sh "yes | fvm use #{flutter_version} -f"
      sh "fvm flutter precache --ios"
    end
    
  end
  install_dependencies(flutter_version)
end

# Manage change log (read from file or prompt user)
def manage_change_log(change_log_file, skip_setup, change_log_input)
  # Read from file if it exists (means it was passed from a parent process like the 'flutter' lane)
  if File.exist?(change_log_file)
    UI.message("Reading change log from #{change_log_file}")
    return File.read(change_log_file)
  end

  # --- This part should ideally NOT be reached when called via `sh` ---
  # Use provided input if available (relevant for internal lane calls, less so for `sh`)
  if change_log_input
    UI.important("Reading change log from provided input (fallback).")
    # Write to file just in case, though ideally the parent already did.
    File.write(change_log_file, change_log_input)
    return change_log_input
  end

  # Prompt user if no file or input exists (THIS IS WHAT CAUSED THE ERROR)
  UI.important("Change log file '#{change_log_file}' not found and no input provided.")
  UI.important("Prompting for change log (fallback - should not happen in CI/sh)...")
  change_log = get_multiline_input("Enter the change log")
  File.write(change_log_file, change_log) # Save for potential reuse if needed
  change_log
end


# Fetch latest build number from Firebase
def fetch_latest_build_number_from_firebase(platform, flavor)
  app_id = get_firebase_app_id(platform, flavor)

  UI.message("Fetching latest build number from Firebase for app ID: #{app_id}")
  begin
    result = firebase_app_distribution_get_latest_release(
      app: app_id,
      service_credentials_file: get_firebase_credential_file(flavor)
    )
    UI.message("Firebase App Distribution response: #{result}")
    latest_build_number = result&.dig(:buildVersion)&.to_i || 0
    UI.message("Latest Firebase build number: #{latest_build_number}")
    latest_build_number
  rescue => e
    UI.error("Error fetching latest Firebase build number: #{e.message}")
    UI.user_error!("Failed to fetch the latest release from Firebase.")
  end
end

# Fetch latest build number from App Store Connect
def fetch_latest_build_number_app_store(bundle_id, version)
  UI.message("Fetching latest build number from App Store Connect for version #{version}")
  begin
    # Ensure API key is configured
    app_store_connect_api_key(
      key_id: APP_STORE_CONNECT_API_KEY_ID,
      issuer_id: APP_STORE_CONNECT_ISSUER_ID,
      key_filepath: APP_STORE_CONNECT_KEY_FILEPATH,
    )
    latest_build = latest_testflight_build_number(
      app_identifier: bundle_id,
      version: version,
      # platform: "ios", # Default is ios
      # initial_build_number: 0 # Default is 1 if no builds exist
    )
    UI.message("Latest TestFlight build number: #{latest_build}")
    latest_build
  rescue => e
    UI.error("Error fetching latest App Store build number: #{e.message}")
    UI.user_error!("Failed to fetch the latest build number from App Store Connect.")
  end
end

# Fetch latest build number from Google Play
def fetch_latest_build_number_google_play(bundle_id, track, flavor)
  UI.message("Fetching latest build number from Google Play for track '#{track}'")
  google_play_key_path = (flavor == 'dev' && File.exist?(GOOGLE_PLAY_KEY_DEV)) ? GOOGLE_PLAY_KEY_DEV : GOOGLE_PLAY_KEY_PROD
  UI.message("Using Google Play key: #{google_play_key_path}")
  begin
    validate_play_store_json_key(json_key: google_play_key_path)
    version_codes = google_play_track_version_codes(
      package_name: bundle_id,
      track: track,
      json_key: google_play_key_path
    )
    latest_build = version_codes.empty? ? 0 : version_codes.max
    UI.message("Latest Google Play build number: #{latest_build}")
    latest_build
  rescue => e
    UI.error("Error fetching latest Google Play build number: #{e.message}")
    UI.user_error!("Failed to fetch the latest build number from Google Play.")
  end
end

# Determine the final build number
def determine_build_number(platform:, flavor:, version:, bundle_id:, distribute_store:, distribute_firebase:, track:, build_number_input:)
  if build_number_input && build_number_input != 'auto'
    return build_number_input.to_i # Use user-provided number
  end

  # Auto-increment logic
  latest_build_number = 0
  if distribute_store
    if platform == :ios
      latest_build_number = fetch_latest_build_number_app_store(bundle_id, version)
    elsif platform == :android
      latest_build_number = fetch_latest_build_number_google_play(bundle_id, track, flavor)
    end
  elsif distribute_firebase # Only check Firebase if not distributing to store
    latest_build_number = fetch_latest_build_number_from_firebase(platform, flavor)
  else
    # If not distributing anywhere and set to auto, maybe default to 1 or fetch from Firebase as a fallback?
    UI.important("Auto build number selected, but no distribution target specified for auto-increment. Fetching from Firebase as fallback.")
    latest_build_number = fetch_latest_build_number_from_firebase(platform, flavor)
  end

  final_build_number = latest_build_number + 1
  UI.message("Determined build number: #{final_build_number}")
  final_build_number
end

# Run the Flutter build command
def run_flutter_build(platform:, flavor:, version:, build_number:, flutter_version:, build_type: nil)
  # For iOS, ensure CocoaPods are installed and up-to-date before building.
  # This replicates the logic of removing the lockfile to force a fresh dependency resolution.
  if platform == :ios
    UI.important("Ensuring fresh CocoaPods dependencies for the iOS build...")
    Dir.chdir("../ios") do
      if File.exist?("Podfile.lock")
        FileUtils.rm("Podfile.lock")
      end
      sh "pod deintegrate && pod install --repo-update"
    end
  end
  prefix = flutter_version == 'stable' ? "" : "fvm "
  UI.header("Building Flutter App (Platform: #{platform}, Flavor: #{flavor || 'default'})")
  build_command = "#{prefix}flutter build"
  build_command += platform == :ios ? " ipa" : " #{build_type}" # ipa for ios, apk/aab for android
  
  # Conditionally add flavor
  if flavor && !flavor.empty?
    build_command += " --flavor=#{flavor}"
  end

  build_command += " --build-name=#{version}"
  build_command += " --build-number=#{build_number}"

  # Conditionally add --dart-define-from-file
  dart_define_file = get_dart_define_file(flavor)
  unless File.exist?("../#{dart_define_file}")
    UI.user_error!(
      "Dart define file 'app/#{dart_define_file}' not found for flavor " \
      "'#{flavor}'. Building without it would ship empty " \
      "String.fromEnvironment values (API base URL, keys), so this is " \
      "a hard failure. Create the file first."
    )
  end
  build_command += " --dart-define-from-file=#{dart_define_file}"

  build_command += " --obfuscate --split-debug-info=./obfuscate/" # Obfuscation flags
  build_command += " --no-tree-shake-icons" # Common flag
  build_command += " --verbose" # Common flag

  # Platform specific flags
  begin
    if platform == :ios
      export_plist_path = nil
      if flavor && !flavor.empty?
        # Flavor-specific path
        export_plist_path = "ios/flavors/#{flavor}/ExportOptions.plist"
      else
        # Non-flavor path
        export_plist_path = "ios/ExportOptions.plist"
      end

      if export_plist_path && File.exist?("../#{export_plist_path}")
        build_command += " --export-options-plist=#{export_plist_path}"
      else
        UI.important("ExportOptions.plist not found at ../#{export_plist_path}. The build may use default export options or fail if they are required.")
      end
    end
  rescue Errno::ENOENT => e
    UI.error("Error accessing ExportOptions.plist: #{e.message}")
  rescue StandardError => e
    UI.error("--export-options-plist error: #{e.message}")
  end

  Dir.chdir(APP_DIR) do
    sh build_command
  end

  # Retry xcodebuild export if flutter build ipa archived successfully but export failed
  if platform == :ios
    ipa_pattern = File.expand_path("build/ios/ipa/*.ipa", APP_DIR)
    archive_path = File.expand_path("build/ios/archive/Runner.xcarchive", APP_DIR)
    found_ipas = Dir.glob(ipa_pattern)

    if found_ipas.empty? && File.directory?(archive_path)
      export_plist = flavor && !flavor.empty? ? "ios/flavors/#{flavor}/ExportOptions.plist" : "ios/ExportOptions.plist"
      max_retries = 3
      max_retries.times do |attempt|
        UI.important("IPA not found but archive exists. Retrying export (attempt #{attempt + 1}/#{max_retries})...")
        FileUtils.rm_rf(File.expand_path("build/ios/ipa", APP_DIR))
        Dir.chdir(APP_DIR) do
          sh(
            "/usr/bin/arch -arm64e xcrun xcodebuild -exportArchive " \
            "-allowProvisioningDeviceRegistration -allowProvisioningUpdates " \
            "-archivePath build/ios/archive/Runner.xcarchive " \
            "-exportPath build/ios/ipa " \
            "-exportOptionsPlist #{export_plist}",
            error_callback: ->(_) { UI.important("Export attempt #{attempt + 1} failed") }
          )
        end
        found_ipas = Dir.glob(ipa_pattern)
        break unless found_ipas.empty?
        sleep(5) if found_ipas.empty? && attempt < max_retries - 1
      end
    end
  end

# Determine and verify output path
  artifact_relative_path = case platform
                           when :ios
                             # Use Dir.glob to find the actual IPA file within the project root
                             ipa_pattern = File.expand_path("build/ios/ipa/*.ipa", APP_DIR)
                             found_ipas = Dir.glob(ipa_pattern) # Search relative to the Fastfile directory

                             # Check if any IPA was found
                             UI.user_error!("Build artifact not found matching pattern: #{ipa_pattern}") if found_ipas.empty?

                             # Log if multiple found, but proceed with the first one found by glob
                             if found_ipas.length > 1
                               UI.important("Warning: Multiple IPAs found matching pattern. Using the first one: #{found_ipas.first}")
                             end

                             # Get the full path of the first found IPA
                             actual_ipa_full_path = found_ipas.first

                             # Convert the full path back to a path relative to the Fastfile directory
                             # This is needed because subsequent actions (like upload_to_testflight)
                             # often expect paths relative to the Fastfile.
                             Pathname.new(actual_ipa_full_path).relative_path_from(Pathname.new(File.expand_path("..", __dir__))).to_s

                           when :android
                             # Android path logic remains the same as it uses specific names
                             base_filename = "app"
                             if flavor && !flavor.empty?
                               base_filename += "-#{flavor}"
                             end
                             
                             relative_path = if build_type == "apk"
                                               "build/app/outputs/flutter-apk/#{base_filename}-release.apk"
                                             else # aab
                                               # Flutter uses "{flavor}Release" for directory, not "app-{flavor}Release"
                                               dir_name = (flavor && !flavor.empty?) ? "#{flavor}Release" : "release"
                                               "build/app/outputs/bundle/#{dir_name}/#{base_filename}-release.aab"
                                             end
                             full_output_path = File.expand_path(relative_path, APP_DIR) # Path relative to project root
                             # File.exist? works here because the path is specific
                             UI.user_error!("Build artifact not found at path: #{full_output_path}") unless File.exist?(full_output_path)
                             relative_path # Return the relative path
                           end

  # Use the determined relative path for logging and return value
  # Log the path relative to the project root for clarity
  full_artifact_path_for_logging = File.expand_path(artifact_relative_path, File.expand_path("..", __dir__))
  UI.success("Build successful! Artifact found at: #{full_artifact_path_for_logging}")

  # Return the path relative to the Fastfile directory for use in other actions
  artifact_relative_path
end

# Distribute to App Store (TestFlight)
def distribute_to_app_store(ipa_path, flavor)
  UI.header("Distributing to App Store (TestFlight)")

  # Use xcrun altool directly instead of upload_to_testflight
  # Fastlane's altool wrapper has compatibility issues with Xcode 26's avtool
  ipa_full_path = File.expand_path(ipa_path, File.expand_path("..", __dir__))
  UI.message("Uploading #{ipa_full_path} via xcrun altool...")

  # --apple-id: skip slow Bundle ID -> Apple ID lookup API call
  apple_id = APP_STORE_CONNECT_APPLE_IDS[flavor]
  UI.user_error!("Unknown flavor for apple-id mapping: #{flavor}") unless apple_id

  altool_cmd = "xcrun altool --upload-app --type ios " \
    "-f #{ipa_full_path.shellescape} " \
    "--apple-id #{apple_id} " \
    "--apiKey #{APP_STORE_CONNECT_API_KEY_ID} " \
    "--apiIssuer #{APP_STORE_CONNECT_ISSUER_ID}"

  Dir.chdir("../") do
    UI.message("Uploading via altool...")
    pid = Process.spawn(altool_cmd)
    _, status = Process.wait2(pid)
    UI.user_error!("altool exited with status #{status.exitstatus}") unless status.success?
  end

  UI.success("Successfully uploaded to App Store Connect via altool")
  "[TestFlight link]"
end

# Distribute to Google Play Store
def distribute_to_google_play(artifact_path, build_type, bundle_id, flavor, track)
  UI.header("Distributing to Google Play Store (Track: #{track})")
  google_play_key_path = (flavor == 'dev' && File.exist?(GOOGLE_PLAY_KEY_DEV)) ? GOOGLE_PLAY_KEY_DEV : GOOGLE_PLAY_KEY_PROD
  is_aab = build_type == 'aab'

  # Upload the artifact
  upload_to_play_store(
    track: track,
    package_name: bundle_id,
    json_key: google_play_key_path,
    aab: is_aab ? "#{artifact_path}" : nil,
    apk: is_aab ? nil : "#{artifact_path}",
    skip_upload_metadata: true,
    skip_upload_images: true,
    skip_upload_screenshots: true,
    skip_upload_changelogs: false, # Consider uploading changelogs if needed
    release_status: 'draft' # Or 'completed' or 'inProgress'
  )

  # Optional: Promote track if needed (example)
  # upload_to_play_store(
  #   track: track,
  #   package_name: bundle_id,
  #   json_key: google_play_key_path,
  #   track_promote_to: "production", # Example: Promote internal track to production
  #   skip_upload_apk: true,
  #   skip_upload_aab: true,
  #   skip_upload_metadata: true,
  #   skip_upload_images: true,
  #   skip_upload_screenshots: true
  # )

  # Construct console link (Note: Account ID might be needed instead of bundle_id for the URL)
  # Fetching the correct account ID programmatically is complex. Using a placeholder.
  google_play_account_id = CONFIG.dig('google_play', 'account_id') || "YOUR_ACCOUNT_ID"
  "Google Play Console"
end

# Distribute to Firebase App Distribution
def distribute_to_firebase(platform, artifact_path, build_type, flavor, change_log)
  UI.header("Distributing to Firebase App Distribution")
  app_id = get_firebase_app_id(platform, flavor)
  firebase_credential_file = get_firebase_credential_file(flavor)

  params = {
    app: app_id,
    service_credentials_file: firebase_credential_file,
    testers_file: FIREBASE_TESTERS_FILE,
    release_notes: change_log
  }

  if platform == :ios
    params[:ipa_path] = "#{artifact_path}"
  else # android
    params[:apk_path] = "#{artifact_path}" # Note: firebase_app_distribution uses :apk_path for both apk and aab
    params[:android_artifact_type] = build_type.upcase if build_type # Specify AAB or APK
  end

  result = firebase_app_distribution(params)
  download_link = result&.dig(:testingUri)
  download_link ? "Firebase Download Link" : "[Firebase Distribution]"
end

# --- Shared Build Logic ---

# Common build logic encapsulated
def run_build(platform:, options:)
  # --- 1. Gather Inputs ---
  is_store_lane = options[:is_store_lane] || false
  
  if is_store_lane
    flavor = 'prod'
  else
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
  end

  flutter_version = options[:flutter_version] || get_input("Enter the Flutter version", CONFIG.dig('flutter', 'default_version') || 'stable')
  version = options[:version] || get_input("Enter the app version", DEFAULT_APP_VERSION)
  build_number_input = options[:build_number] || get_build_number_input("Enter build number ('auto' for auto-increment)", 'auto')
  skip_setup = options[:skip_setup].nil? ? false : options[:skip_setup]
  change_log_file = platform == :ios ? CHANGE_LOG_IOS_FILE : CHANGE_LOG_ANDROID_FILE

  # Platform specific inputs
  if platform == :android
    build_type = is_store_lane ? 'aab' : (options[:build_type] || get_validated_input("Build to apk or aab?", VALID_BUILD_TYPES, "apk"))
  else
    build_type = nil # Not applicable for iOS build command
  end

  # Distribution options
  if is_store_lane
    distribute_store = true
    distribute_firebase = false
    track = platform == :android ? (options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal")) : nil
  else
    distribute_store = options[:distribute_store].nil? ? get_boolean_input("Distribute to #{platform == :ios ? 'App Store' : 'Play Store'}?", false) : options[:distribute_store]
    distribute_firebase = options[:distribute_firebase].nil? ? get_boolean_input("Distribute to Firebase?", !distribute_store) : options[:distribute_firebase] # Default firebase=true if store=false
    track = (platform == :android && distribute_store) ? (options[:track] || get_validated_input("Enter Play Store track", VALID_TRACKS, "internal")) : nil
  end

  # --- 2. Manage Change Log ---
  # Note: change_log_input is only relevant if passed from a combined lane that uses internal calls.
  # With the `sh` approach, the combined lane writes to the file, and this function reads it.
  change_log = manage_change_log(change_log_file, skip_setup, options[:change_log])

  # --- 3. Determine Bundle ID ---
  base_bundle_id = CONFIG.dig('app_bundle_ids', platform.to_s)
  UI.user_error!("'app_bundle_ids' for platform '#{platform}' not set in #{CONFIG_FILE}.") unless base_bundle_id
  bundle_id = get_bundle_id_with_suffix(base_bundle_id, flavor)

  # --- 4. Determine Build Number ---
  build_number = determine_build_number(
    platform: platform,
    flavor: flavor,
    version: version,
    bundle_id: bundle_id,
    distribute_store: distribute_store,
    distribute_firebase: distribute_firebase,
    track: track,
    build_number_input: build_number_input
  )

  # --- 5. Setup Environment ---
  skip_build = options[:skip_build] || false
  unless skip_build
    setup_flutter_environment(flutter_version, skip_setup)
  end

  # --- 6. Build ---
  if skip_build
    UI.header("Skipping build — using existing artifact")
    artifact_path = case platform
                    when :ios
                      ipa_pattern = "../build/ios/ipa/*.ipa"
                      found_ipas = Dir.glob(ipa_pattern)
                      UI.user_error!("No existing IPA found at #{ipa_pattern}. Build first.") if found_ipas.empty?
                      found_ipas.first.sub(/^\.\.\//, '')
                    when :android
                      base_filename = "app"
                      base_filename += "-#{flavor}" if flavor && !flavor.empty?
                      relative_path = if build_type == "apk"
                                        "build/app/outputs/flutter-apk/#{base_filename}-release.apk"
                                      else
                                        dir_name = (flavor && !flavor.empty?) ? "#{flavor}Release" : "release"
                                        "build/app/outputs/bundle/#{dir_name}/#{base_filename}-release.aab"
                                      end
                      UI.user_error!("No existing artifact found at ../#{relative_path}. Build first.") unless File.exist?("../#{relative_path}")
                      relative_path
                    end
    UI.success("Found existing artifact: #{artifact_path}")
  else
    artifact_path = run_flutter_build(
      platform: platform,
      flavor: flavor,
      version: version,
      build_number: build_number,
      build_type: build_type,
      flutter_version: flutter_version
    )
  end

  # --- 7. Distribute ---
  download_links = []
  if distribute_store
    if platform == :ios
      download_links << distribute_to_app_store(artifact_path, flavor)
    elsif platform == :android
      download_links << distribute_to_google_play(artifact_path, build_type, bundle_id, flavor, track)
    end
  end
  if distribute_firebase
    download_links << distribute_to_firebase(platform, artifact_path, build_type, flavor, change_log)
  end

  # --- 8. Cleanup ---
  # File.delete(change_log_file) if File.exist?(change_log_file) # Cleanup moved to combined lanes
  UI.success("#{platform.to_s.capitalize} build and distribution complete for #{version}+#{build_number} (#{flavor})")

rescue => exception
  UI.error("Error in #{platform.to_s} lane: #{exception.message}")
  # Optional: Send error notification to Discord
  raise # Re-raise the error to fail the lane
ensure
  # Cleanup actions that should always run, e.g., deleting temp files
  # File.delete(change_log_file) if File.exist?(change_log_file) # Cleanup moved to combined lanes
end
