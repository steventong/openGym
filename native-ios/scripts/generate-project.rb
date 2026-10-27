require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'OpenGym.xcodeproj'))

# Mirror the on-disk directories in Xcode's navigator, with group-relative paths.
def grouped_file(project, relative_path)
  components = relative_path.split('/')
  filename = components.pop
  group = components.reduce(project.main_group) do |parent, directory|
    parent.groups.find { |child| child.path == directory } || parent.new_group(directory, directory)
  end
  group.new_file(filename)
end

app = project.new_target(:application, 'OpenGym', :ios, '17.0')
app.build_configurations.each do |c|
  c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'INFOPLIST_KEY_CFBundleDisplayName'=>'OpenGYM', 'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'=>'NO', 'INFOPLIST_KEY_UISupportedInterfaceOrientations'=>'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'=>'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight', 'INFOPLIST_KEY_UILaunchScreen_Generation'=>'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation'=>'YES', 'INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking'=>'YES', 'INFOPLIST_FILE'=>'OpenGym/Info.plist', 'TARGETED_DEVICE_FAMILY'=>'1,2', 'CODE_SIGN_STYLE'=>'Automatic', 'DEVELOPMENT_TEAM'=>'HHH7WTMLVN', 'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon', 'CODE_SIGN_ENTITLEMENTS'=>'OpenGym/OpenGym.entitlements', 'CURRENT_PROJECT_VERSION'=>'1', 'MARKETING_VERSION'=>'1.0.0'})
end
Dir.glob(File.join(root, 'OpenGym/**/*.swift')).sort.each { |p| app.add_file_references([grouped_file(project, p.sub(root+'/', ''))]) }
Dir.glob(File.join(root, 'OpenGym/Resources/*')).sort.each { |p| app.resources_build_phase.add_file_reference(grouped_file(project, p.sub(root+'/', ''))) }
%w[OpenGym/Info.plist OpenGym/OpenGym.entitlements].each { |path| grouped_file(project, path) }
tests = project.new_target(:unit_test_bundle, 'OpenGymTests', :ios, '17.0')
tests.add_dependency(app)
tests.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym.tests', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'TEST_HOST'=>'$(BUILT_PRODUCTS_DIR)/OpenGym.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OpenGym', 'BUNDLE_LOADER'=>'$(TEST_HOST)'})
end
Dir.glob(File.join(root, 'OpenGymTests/*.swift')).sort.each { |p| tests.add_file_references([grouped_file(project, p.sub(root+'/', ''))]) }
project.main_group.children.sort_by! { |child| [%w[OpenGym OpenGymTests Frameworks Products].index(child.display_name) || 4, child.display_name] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(root+'/OpenGym.xcodeproj', 'OpenGym', true)
