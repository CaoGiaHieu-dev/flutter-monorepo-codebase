# --- Configuration ---
require 'yaml'
require 'json'
require 'timeout'
require 'pathname'
require 'fileutils'
require 'shellwords'
require 'open3'
require 'tmpdir'

# Every path in these modules is ABSOLUTE and derived from this file's own
# location — never from the working directory. Fastlane can be started from
# the repository root (root `fastlane/Fastfile`, lanes run in `<root>/fastlane`,
# actions in `<root>`) or from `apps/mobile/` (lanes in `apps/mobile/fastlane`,
# actions in `apps/mobile`), so a CWD-relative path such as `../env.dev` points
# at a different file depending on the entry point.
FASTLANE_DIR = File.expand_path("..", __dir__)   # apps/mobile/fastlane
APP_DIR = File.expand_path("..", FASTLANE_DIR)   # apps/mobile
CONFIG_FILE = File.join(FASTLANE_DIR, "Config.yaml")

# The workspace root is found by walking up until a pubspec.yaml declaring a
# `workspace:` list turns up — not by counting `..` from APP_DIR. The app moved
# from `app/` to `apps/mobile/` and a hardcoded level made the root resolve to
# `apps/`, where dependency installation quietly did nothing useful.
def find_workspace_root(start)
  dir = start
  loop do
    pubspec = File.join(dir, "pubspec.yaml")
    return dir if File.exist?(pubspec) && File.read(pubspec).match?(/^workspace:/)
    parent = File.dirname(dir)
    break if parent == dir
    dir = parent
  end
  UI.user_error!("No pubspec.yaml with a `workspace:` list found above #{start}")
end

WORKSPACE_ROOT = find_workspace_root(APP_DIR)

UI.user_error!("Configuration file not found at #{CONFIG_FILE}. Copy Config.example.yaml next to it and fill it in.") unless File.exist?(CONFIG_FILE)
CONFIG = YAML.load_file(CONFIG_FILE)

# A path from Config.yaml. Absolute paths are kept; relative ones are resolved
# against APP_DIR (apps/mobile/) — the same file whichever directory fastlane
# was started from. Returns nil when the key is unset.
def resolve_app_path(path)
  return nil if path.nil? || path.to_s.strip.empty?
  File.expand_path(path.to_s, APP_DIR)
end

# A path for log messages, relative to the repository root.
def display_path(path)
  Pathname.new(path).relative_path_from(Pathname.new(WORKSPACE_ROOT)).to_s
rescue ArgumentError
  path
end

# Default App Version (now loaded from YAML)
DEFAULT_APP_VERSION = CONFIG.dig('default_app_version')

# Credentials and paths are loaded from Config.yaml and made absolute.
FIREBASE_TESTERS_FILE = resolve_app_path(CONFIG.dig('paths', 'firebase_testers_file'))
GOOGLE_PLAY_KEY_PROD = resolve_app_path(CONFIG.dig('paths', 'google_play_key_prod'))
GOOGLE_PLAY_KEY_DEV = resolve_app_path(CONFIG.dig('paths', 'google_play_key_dev'))
APP_STORE_CONNECT_KEY_FILEPATH = resolve_app_path(CONFIG.dig('paths', 'app_store_connect_key_filepath'))
APP_STORE_CONNECT_APPLE_IDS = CONFIG.dig('app_store_connect', 'apple_ids') || {}

# App Store Credentials (now loaded from YAML)
APP_STORE_CONNECT_API_KEY_ID = CONFIG.dig('app_store_connect', 'api_key_id') || ""
APP_STORE_CONNECT_ISSUER_ID = CONFIG.dig('app_store_connect', 'issuer_id') || ""
APP_STORE_USERNAME = CONFIG.dig('app_store_connect', 'username') || ""
APP_STORE_TEAM_ID = CONFIG.dig('app_store_connect', 'team_id') || ""

# Valid options
VALID_FLAVORS = (CONFIG.dig('valid_flavors') || []) + ['none']
VALID_TRACKS = ['production', 'internal', 'closed']
VALID_BUILD_TYPES = ['apk', 'aab']

# --- Toolchain (FVM is optional) ---
#
# FVM is used only when BOTH hold — the same rule as tools/shared/toolchain.dart:
# the workspace pins a version (`.fvmrc`, or the legacy `.fvm/fvm_config.json`)
# AND `fvm` is installed on this machine. Either alone gives a wrong answer: a
# CI runner has the pin but no fvm, a laptop can have fvm for other projects.
# FASTLANE_USE_FVM=true|false overrides the detection.
def detect_fvm
  override = ENV['FASTLANE_USE_FVM'].to_s.strip.downcase
  return true if %w[1 true yes].include?(override)
  return false if %w[0 false no].include?(override)

  pinned = File.exist?(File.join(WORKSPACE_ROOT, ".fvmrc")) ||
           File.exist?(File.join(WORKSPACE_ROOT, ".fvm", "fvm_config.json"))
  return false unless pinned
  begin
    _out, status = Open3.capture2e("fvm", "--version")
    status.success?
  rescue SystemCallError
    false
  end
end

USE_FVM = detect_fvm

def flutter_cmd
  USE_FVM ? "fvm flutter" : "flutter"
end

def dart_cmd
  USE_FVM ? "fvm dart" : "dart"
end

# The version `.fvmrc` pins, or nil.
def fvm_pinned_version
  fvmrc = File.join(WORKSPACE_ROOT, ".fvmrc")
  return nil unless File.exist?(fvmrc)
  JSON.parse(File.read(fvmrc))['flutter']
rescue JSON::ParserError
  nil
end

# `flutter_version` is either `stable` (or empty): "use whatever Flutter this
# machine resolves — the FVM pin, else the one on PATH", or an exact version
# the build must be made with. Returns nil for the former.
def requested_flutter_version(flutter_version)
  v = flutter_version.to_s.strip
  return nil if v.empty? || v.casecmp('stable').zero?
  v
end

# The framework version of the Flutter that `flutter_cmd` runs, or nil.
def installed_flutter_version
  out, status = Open3.capture2e(*flutter_cmd.split, "--version", "--machine")
  return nil unless status.success?
  json = out[/\{.*\}/m]
  json ? JSON.parse(json)['frameworkVersion'] : nil
rescue SystemCallError, JSON::ParserError
  nil
end

# --- Helper Functions ---

# Get bundle ID with suffix based on flavor and platform. The suffixes differ
# per platform and must match the native projects: Android's
# `applicationIdSuffix` (android/app/build.gradle.kts: `.dev`, `.stg`) and iOS's
# `PRODUCT_BUNDLE_IDENTIFIER` (ios/Runner.xcodeproj: `.dev`, `.staging`).
def get_bundle_id_with_suffix(base_bundle_id, flavor, platform)
  return base_bundle_id if flavor.nil? || flavor.empty?
  case flavor
  when 'dev' then "#{base_bundle_id}.dev"
  when 'staging' then platform == :ios ? "#{base_bundle_id}.staging" : "#{base_bundle_id}.stg"
  else base_bundle_id
  end
end

# Get dart define file name (inside apps/mobile/) based on flavor
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

# `build_number` as passed on the command line or typed at the prompt.
# `auto`, an empty value (`build_number:` — what a CI input left blank
# produces) and nil all mean "work it out" (see determine_build_number).
# Anything else must be a positive integer: `"".to_i` / `"abc".to_i` are 0,
# and a silent `--build-number=0` is exactly what this used to ship.
def normalize_build_number_input(value)
  s = value.to_s.strip
  return 'auto' if s.empty? || s.casecmp('auto').zero?
  UI.user_error!("Invalid build_number '#{s}': pass a positive integer or 'auto'.") unless s.match?(/\A[1-9]\d*\z/)
  s.to_i
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

# Helper to get the (absolute) Firebase credential file path based on flavor
def get_firebase_credential_file(flavor)
  actual_flavor_key = (flavor && !flavor.empty?) ? flavor : 'default'
  credential_file = CONFIG.dig('firebase', 'credentials_map', actual_flavor_key)
  UI.user_error!("Firebase credential file path for flavor '#{actual_flavor_key}' not set in #{CONFIG_FILE}.") unless credential_file
  resolve_app_path(credential_file)
end

# The Google Play service-account key for a flavor: the dev key for `dev` when
# it is configured and present, the prod key otherwise.
def google_play_key_for(flavor)
  (flavor == 'dev' && GOOGLE_PLAY_KEY_DEV && File.exist?(GOOGLE_PLAY_KEY_DEV)) ? GOOGLE_PLAY_KEY_DEV : GOOGLE_PLAY_KEY_PROD
end

# Install project dependencies
def install_dependencies
  UI.header("Installing Dependencies (#{USE_FVM ? 'via fvm' : 'global flutter/dart'})")
  Dir.chdir(APP_DIR) do
    sh "#{dart_cmd} pub global activate flutterfire_cli"
    sh "#{dart_cmd} pub global activate flutter_gen"
    sh "#{flutter_cmd} clean"
    # The workspace pubspec.lock is committed: a release is built from exactly
    # the versions in it, and a lockfile that no longer matches the pubspecs
    # fails here instead of being silently re-resolved.
    sh "#{flutter_cmd} pub get --enforce-lockfile"
  end

  # Conditionally run 'flutter gen-l10n' for all features.
  # Scanned from the workspace root rather than a `packages/` subtree: that
  # directory no longer exists, and any assumption about where packages sit
  # makes this loop silently generate nothing the day they move.
  UI.message("Scanning for l10n.yaml files in workspace to run 'flutter gen-l10n'...")
  l10n_files = Dir.glob(File.join(WORKSPACE_ROOT, "**", "l10n.yaml"))
                  .reject { |f| f.include?("/build/") || f.include?("/.dart_tool/") }

  if l10n_files.empty?
    UI.message("No l10n.yaml found in workspace, skipping 'flutter gen-l10n'.")
  else
    l10n_files.each do |l10n_file|
      pkg_dir = File.dirname(l10n_file)
      UI.message("Found l10n.yaml in #{pkg_dir}. Running 'flutter gen-l10n'...")
      Dir.chdir(pkg_dir) do
        sh "#{flutter_cmd} gen-l10n"
      end
    end
  end

  # Run 'build_runner' for the entire workspace
  UI.message("Running build_runner for workspace...")
  Dir.chdir(WORKSPACE_ROOT) do
    sh "#{dart_cmd} run build_runner build --workspace"
  end

  # Generate barrel files — one package at a time, after gen-l10n and
  # build_runner, because a barrel also exports the generated files on disk.
  # The `lib/src/gen/gen.dart` barrels are gitignored, so on a clean runner
  # nothing compiles until this has run. Mirrors step 6 of
  # tools/workspace_setup/configure.dart: same skipped directories, and an app
  # (a dir with `app_manifest.yaml`) is skipped — it is a composition root, and
  # its `injection.dart` is composer's output, compared byte-for-byte.
  UI.message("Generating barrel files per package...")
  skipped_dirs = %w[build .dart_tool ios android macos windows linux web node_modules]
  Dir.chdir(WORKSPACE_ROOT) do
    # Relative paths, as configure.dart passes them.
    pubspecs = Dir.glob(File.join("**", "pubspec.yaml"))
                  .reject { |f| f.split("/").any? { |s| skipped_dirs.include?(s) } }
                  .sort
    pubspecs.each do |pubspec|
      pkg_dir = File.dirname(pubspec)
      lib_dir = File.join(pkg_dir, "lib")
      next unless Dir.exist?(lib_dir)
      next if File.exist?(File.join(pkg_dir, "app_manifest.yaml"))
      sh "#{dart_cmd} tools/barrel_generator/generate.dart #{lib_dir.shellescape}"
    end
  end
end

# Setup Flutter environment (version check and dependencies).
#
# Nothing here changes which Flutter is installed unless asked to:
# - with FVM detected, `fvm install` fetches the version `.fvmrc` pins, and a
#   different `flutter_version` is an error (switching would rewrite the
#   tracked `.fvmrc` behind your back);
# - without FVM, the Flutter on PATH is used as is, and an exact
#   `flutter_version` must match it;
# - `flutter_upgrade:true` (opt-in) runs `flutter channel stable` +
#   `flutter upgrade --force` on the global Flutter first. It used to run on
#   every `stable` build, silently moving the machine's toolchain.
def setup_flutter_environment(flutter_version, skip_setup, platforms: [], upgrade: false)
  return if skip_setup
  requested = requested_flutter_version(flutter_version)
  UI.header("Setting up Flutter Environment (requested: #{requested || 'any'}, fvm: #{USE_FVM})")

  if USE_FVM
    pinned = fvm_pinned_version
    if requested && pinned && requested != pinned
      UI.user_error!(
        "flutter_version:#{requested} was requested, but .fvmrc pins #{pinned}. " \
        "Run `fvm use #{requested}` and commit .fvmrc, or pass flutter_version:stable " \
        "to build with the pinned version."
      )
    end
    UI.important("flutter_upgrade ignored: the Flutter version comes from .fvmrc.") if upgrade
    Dir.chdir(WORKSPACE_ROOT) { sh "fvm install" }
  else
    if upgrade
      sh "flutter channel stable"
      sh "flutter upgrade --force"
    end
    if requested
      installed = installed_flutter_version
      if installed.nil?
        UI.important("Could not determine the installed Flutter version; expected #{requested}.")
      elsif installed != requested
        UI.user_error!(
          "flutter_version:#{requested} was requested, but the Flutter on PATH is #{installed}. " \
          "Install #{requested} (or install fvm), or pass flutter_version:stable to build with #{installed}."
        )
      end
    end
  end

  if platforms.include?(:ios) && FastlaneCore::Helper.mac?
    sh "#{flutter_cmd} precache --ios"
  end
  install_dependencies
end

# The change log for a build, in order of precedence:
#   1. the `change_log:` option — always wins;
#   2. `change_log_file:` — the file a combined lane (`flutter` / `store`)
#      wrote for its child processes, read only when explicitly passed;
#   3. an interactive prompt.
# Nothing is written back to disk. The old version read a fixed
# `change_log_<platform>.txt` BEFORE looking at the option, so a file left by
# an earlier (crashed) run silently replaced the change log you passed.
def resolve_change_log(change_log_input, change_log_file)
  unless change_log_input.nil? || change_log_input.to_s.strip.empty?
    return change_log_input.to_s
  end

  unless change_log_file.nil? || change_log_file.to_s.strip.empty?
    UI.user_error!("change_log_file '#{change_log_file}' does not exist.") unless File.exist?(change_log_file)
    UI.message("Reading change log from #{change_log_file}")
    return File.read(change_log_file)
  end

  get_multiline_input("Enter the change log")
end

# Write a change log to a fresh temp directory (outside the repository) for
# the child lanes of a combined lane. The caller deletes it in an `ensure`.
def write_temp_change_log(change_log)
  dir = Dir.mktmpdir("fastlane-change-log-")
  path = File.join(dir, "change_log.txt")
  File.write(path, change_log)
  path
end

# Run a lane in a child fastlane process from APP_DIR (so it always loads
# apps/mobile/fastlane/Fastfile). Under `bundle exec` the child inherits
# BUNDLE_GEMFILE and resolves the same gems.
def run_child_lane(*args)
  cmd = (["fastlane"] + args.compact.map(&:to_s)).shelljoin
  UI.message("Executing: #{cmd}")
  Dir.chdir(APP_DIR) { sh(cmd) }
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
  google_play_key_path = google_play_key_for(flavor)
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

# The build number in apps/mobile/pubspec.yaml (`version: 1.0.0+N`), or 1.
def pubspec_build_number
  pubspec = YAML.load_file(File.join(APP_DIR, "pubspec.yaml"))
  number = pubspec['version'].to_s[/\+(\d+)\z/, 1]
  number ? number.to_i : 1
end

# Determine the final build number.
#
# A literal number is used as is. `auto` (also an empty value) means:
# - distributing to a store → latest TestFlight (iOS) / Play track (Android) + 1
# - distributing to Firebase → latest Firebase App Distribution release + 1
# - not distributing at all → the build number in apps/mobile/pubspec.yaml,
#   i.e. what a plain `flutter build` would use. Nothing to collide with, and
#   no credentials needed for a local build.
def determine_build_number(platform:, flavor:, version:, bundle_id:, distribute_store:, distribute_firebase:, track:, build_number_input:)
  normalized = normalize_build_number_input(build_number_input)
  return normalized unless normalized == 'auto'

  if distribute_store
    latest_build_number = if platform == :ios
                            fetch_latest_build_number_app_store(bundle_id, version)
                          else
                            fetch_latest_build_number_google_play(bundle_id, track, flavor)
                          end
  elsif distribute_firebase
    latest_build_number = fetch_latest_build_number_from_firebase(platform, flavor)
  else
    build_number = pubspec_build_number
    UI.important("build_number:auto with no distribution target: using the pubspec build number (#{build_number}).")
    return build_number
  end

  final_build_number = latest_build_number.to_i + 1
  UI.message("Determined build number: #{final_build_number}")
  final_build_number
end

# Absolute ExportOptions.plist for an iOS build: the flavor's own when a
# flavor is set, ios/ExportOptions.plist otherwise.
def export_options_plist_for(flavor)
  relative = flavor && !flavor.empty? ? "ios/flavors/#{flavor}/ExportOptions.plist" : "ios/ExportOptions.plist"
  File.join(APP_DIR, relative)
end

# Absolute path of the Android artifact `flutter build` produces.
def android_artifact_path(flavor, build_type)
  base_filename = "app"
  base_filename += "-#{flavor}" if flavor && !flavor.empty?
  relative_path = if build_type == "apk"
                    "build/app/outputs/flutter-apk/#{base_filename}-release.apk"
                  else # aab
                    # Flutter uses "{flavor}Release" for directory, not "app-{flavor}Release"
                    dir_name = (flavor && !flavor.empty?) ? "#{flavor}Release" : "release"
                    "build/app/outputs/bundle/#{dir_name}/#{base_filename}-release.aab"
                  end
  File.join(APP_DIR, relative_path)
end

def ios_ipa_glob
  File.join(APP_DIR, "build", "ios", "ipa", "*.ipa")
end

# Run the Flutter build command. Returns the ABSOLUTE artifact path.
def run_flutter_build(platform:, flavor:, version:, build_number:, build_type: nil)
  # For iOS, ensure CocoaPods are installed and up-to-date before building.
  # This replicates the logic of removing the lockfile to force a fresh dependency resolution.
  if platform == :ios
    UI.important("Ensuring fresh CocoaPods dependencies for the iOS build...")
    Dir.chdir(File.join(APP_DIR, "ios")) do
      FileUtils.rm_f("Podfile.lock")
      sh "pod deintegrate && pod install --repo-update"
    end
  end

  UI.header("Building Flutter App (Platform: #{platform}, Flavor: #{flavor || 'default'})")
  build_command = "#{flutter_cmd} build"
  build_command += platform == :ios ? " ipa" : " #{build_type}" # ipa for ios, apk/aab for android

  # Conditionally add flavor
  if flavor && !flavor.empty?
    build_command += " --flavor=#{flavor}"
  end

  build_command += " --build-name=#{version}"
  build_command += " --build-number=#{build_number}"

  # --dart-define-from-file, absolute so it cannot depend on the CWD
  dart_define_file = File.join(APP_DIR, get_dart_define_file(flavor))
  unless File.exist?(dart_define_file)
    UI.user_error!(
      "Dart define file '#{display_path(dart_define_file)}' not found for flavor " \
      "'#{flavor}'. Building without it would ship empty " \
      "String.fromEnvironment values (API base URL, keys), so this is " \
      "a hard failure. Create the file first."
    )
  end
  build_command += " --dart-define-from-file=#{dart_define_file.shellescape}"

  build_command += " --obfuscate --split-debug-info=#{File.join(APP_DIR, 'obfuscate').shellescape}" # Obfuscation flags
  build_command += " --no-tree-shake-icons" # Common flag
  build_command += " --verbose" # Common flag

  # Platform specific flags
  if platform == :ios
    export_plist_path = export_options_plist_for(flavor)
    if File.exist?(export_plist_path)
      build_command += " --export-options-plist=#{export_plist_path.shellescape}"
    else
      UI.important("ExportOptions.plist not found at #{display_path(export_plist_path)}. The build may use default export options or fail if they are required.")
    end
  end

  Dir.chdir(APP_DIR) do
    sh build_command
  end

  # Retry xcodebuild export if flutter build ipa archived successfully but export failed
  if platform == :ios
    archive_path = File.join(APP_DIR, "build", "ios", "archive", "Runner.xcarchive")
    found_ipas = Dir.glob(ios_ipa_glob)

    if found_ipas.empty? && File.directory?(archive_path)
      export_plist = export_options_plist_for(flavor)
      max_retries = 3
      max_retries.times do |attempt|
        UI.important("IPA not found but archive exists. Retrying export (attempt #{attempt + 1}/#{max_retries})...")
        FileUtils.rm_rf(File.join(APP_DIR, "build", "ios", "ipa"))
        Dir.chdir(APP_DIR) do
          sh(
            "/usr/bin/arch -arm64e xcrun xcodebuild -exportArchive " \
            "-allowProvisioningDeviceRegistration -allowProvisioningUpdates " \
            "-archivePath build/ios/archive/Runner.xcarchive " \
            "-exportPath build/ios/ipa " \
            "-exportOptionsPlist #{export_plist.shellescape}",
            error_callback: ->(_) { UI.important("Export attempt #{attempt + 1} failed") }
          )
        end
        found_ipas = Dir.glob(ios_ipa_glob)
        break unless found_ipas.empty?
        sleep(5) if attempt < max_retries - 1
      end
    end
  end

  # Determine and verify output path
  artifact_path = case platform
                  when :ios
                    found_ipas = Dir.glob(ios_ipa_glob)
                    UI.user_error!("Build artifact not found matching pattern: #{ios_ipa_glob}") if found_ipas.empty?
                    if found_ipas.length > 1
                      UI.important("Warning: Multiple IPAs found matching pattern. Using the first one: #{found_ipas.first}")
                    end
                    found_ipas.first
                  when :android
                    path = android_artifact_path(flavor, build_type)
                    UI.user_error!("Build artifact not found at path: #{path}") unless File.exist?(path)
                    path
                  end

  UI.success("Build successful! Artifact found at: #{artifact_path}")
  artifact_path
end

# Distribute to App Store (TestFlight)
def distribute_to_app_store(ipa_path, flavor)
  UI.header("Distributing to App Store (TestFlight)")

  # Use xcrun altool directly instead of upload_to_testflight
  # Fastlane's altool wrapper has compatibility issues with Xcode 26's avtool
  UI.message("Uploading #{ipa_path} via xcrun altool...")

  # --apple-id: skip slow Bundle ID -> Apple ID lookup API call
  apple_id = APP_STORE_CONNECT_APPLE_IDS[flavor || 'default']
  UI.user_error!("Unknown flavor for apple-id mapping: #{flavor}") unless apple_id

  altool_cmd = "xcrun altool --upload-app --type ios " \
    "-f #{ipa_path.shellescape} " \
    "--apple-id #{apple_id} " \
    "--apiKey #{APP_STORE_CONNECT_API_KEY_ID} " \
    "--apiIssuer #{APP_STORE_CONNECT_ISSUER_ID}"

  Dir.chdir(APP_DIR) do
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
  google_play_key_path = google_play_key_for(flavor)
  is_aab = build_type == 'aab'

  # Upload the artifact
  upload_to_play_store(
    track: track,
    package_name: bundle_id,
    json_key: google_play_key_path,
    aab: is_aab ? artifact_path : nil,
    apk: is_aab ? nil : artifact_path,
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
    release_notes: change_log
  }
  params[:testers_file] = FIREBASE_TESTERS_FILE if FIREBASE_TESTERS_FILE

  if platform == :ios
    params[:ipa_path] = artifact_path
  else # android
    params[:apk_path] = artifact_path # Note: firebase_app_distribution uses :apk_path for both apk and aab
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
  # `options.key?` — `build_number:` with an empty value must mean `auto`, not
  # "prompt" and not 0; normalize_build_number_input handles both.
  build_number_input = options.key?(:build_number) ? options[:build_number] : get_build_number_input("Enter build number ('auto' for auto-increment)", 'auto')
  skip_setup = options[:skip_setup].nil? ? false : options[:skip_setup]

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

  # --- 2. Change Log ---
  change_log = resolve_change_log(options[:change_log], options[:change_log_file])
  UI.message("Change log: #{change_log.to_s.strip.empty? ? '(empty)' : change_log.to_s.strip}")

  # --- 3. Determine Bundle ID ---
  base_bundle_id = CONFIG.dig('app_bundle_ids', platform.to_s)
  UI.user_error!("'app_bundle_ids' for platform '#{platform}' not set in #{CONFIG_FILE}.") unless base_bundle_id
  bundle_id = get_bundle_id_with_suffix(base_bundle_id, flavor, platform)

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
    setup_flutter_environment(flutter_version, skip_setup, platforms: [platform], upgrade: options[:flutter_upgrade] == true)
  end

  # --- 6. Build ---
  if skip_build
    UI.header("Skipping build — using existing artifact")
    artifact_path = case platform
                    when :ios
                      found_ipas = Dir.glob(ios_ipa_glob)
                      UI.user_error!("No existing IPA found at #{ios_ipa_glob}. Build first.") if found_ipas.empty?
                      found_ipas.first
                    when :android
                      path = android_artifact_path(flavor, build_type)
                      UI.user_error!("No existing artifact found at #{path}. Build first.") unless File.exist?(path)
                      path
                    end
    UI.success("Found existing artifact: #{artifact_path}")
  else
    artifact_path = run_flutter_build(
      platform: platform,
      flavor: flavor,
      version: version,
      build_number: build_number,
      build_type: build_type
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

  UI.success("#{platform.to_s.capitalize} build and distribution complete for #{version}+#{build_number} (#{flavor})")

rescue => exception
  UI.error("Error in #{platform.to_s} lane: #{exception.message}")
  # Optional: Send error notification to Discord
  raise # Re-raise the error to fail the lane
end
