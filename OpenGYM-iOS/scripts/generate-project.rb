require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'OpenGYM.xcodeproj'))

# Mirror the on-disk directories in Xcode's navigator, with group-relative paths.
def grouped_file(project, relative_path)
  components = relative_path.split('/')
  filename = components.pop
  group = components.reduce(project.main_group) do |parent, directory|
    parent.groups.find { |child| child.path == directory } || parent.new_group(directory, directory)
  end
  group.new_file(filename)
end

app = project.new_target(:application, 'OpenGYM', :ios, '26.0')
app.build_configurations.each do |c|
  c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'INFOPLIST_KEY_CFBundleDisplayName'=>'OpenGYM', 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'=>'NO', 'INFOPLIST_KEY_UISupportedInterfaceOrientations'=>'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'=>'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation'=>'YES', 'INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking'=>'YES', 'INFOPLIST_FILE'=>'App/Info.plist', 'TARGETED_DEVICE_FAMILY'=>'1,2', 'CODE_SIGN_STYLE'=>'Automatic', 'DEVELOPMENT_TEAM'=>'HHH7WTMLVN', 'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'=>'AccentColor', 'CODE_SIGN_ENTITLEMENTS'=>'App/OpenGYM.entitlements', 'CURRENT_PROJECT_VERSION'=>'1', 'MARKETING_VERSION'=>'1.0.0'})
end
Dir.glob(File.join(root, 'App/**/*.swift')).sort.each do |path|
  app.add_file_references([grouped_file(project, path.delete_prefix(root + '/'))])
end
Dir.glob(File.join(root, 'Resources/*')).sort.each do |path|
  next if File.basename(path) == 'Localization' # Catalog target membership is configured below.
  app.resources_build_phase.add_file_reference(grouped_file(project, path.delete_prefix(root + '/')))
end
%w[App/Info.plist App/OpenGYM.entitlements].each { |path| grouped_file(project, path) }
tests = project.new_target(:unit_test_bundle, 'OpenGYMTests', :ios, '26.0')
tests.add_dependency(app)
tests.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym.tests', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'TEST_HOST'=>'$(BUILT_PRODUCTS_DIR)/OpenGYM.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OpenGYM', 'BUNDLE_LOADER'=>'$(TEST_HOST)'})
end
Dir.glob(File.join(root, 'Tests/*.swift')).sort.each { |p| tests.add_file_references([grouped_file(project, p.sub(root+'/', ''))]) }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(root+'/OpenGYM.xcodeproj', 'OpenGYM', true)

# Add the companion-only watch remote and shared transport models.
require_relative 'configure-watch'
require_relative 'configure-live-activity'
require_relative 'configure-bundled-videos'

require_relative "configure-localization"

project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
project.main_group.children.sort_by! { |child| [%w[App Watch Widgets Shared Resources Tests Frameworks Products].index(child.display_name) || 8, child.display_name] }
project.save
