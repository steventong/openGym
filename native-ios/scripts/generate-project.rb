require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'OpenGym.xcodeproj'))
app = project.new_target(:application, 'OpenGym', :ios, '17.0')
app.build_configurations.each do |c|
  c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'INFOPLIST_KEY_CFBundleDisplayName'=>'openGym', 'INFOPLIST_KEY_UILaunchScreen_Generation'=>'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation'=>'YES', 'INFOPLIST_KEY_NSAppTransportSecurity_NSAllowsLocalNetworking'=>'YES', 'INFOPLIST_FILE'=>'OpenGym/Info.plist', 'TARGETED_DEVICE_FAMILY'=>'1,2', 'CODE_SIGN_STYLE'=>'Automatic', 'DEVELOPMENT_TEAM'=>'HHH7WTMLVN', 'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon', 'CODE_SIGN_ENTITLEMENTS'=>'OpenGym/OpenGym.entitlements', 'CURRENT_PROJECT_VERSION'=>'1', 'MARKETING_VERSION'=>'1.0.0'})
end
Dir.glob(File.join(root, 'OpenGym/**/*.swift')).sort.each { |p| app.add_file_references([project.main_group.new_file(p.sub(root+'/', ''))]) }
Dir.glob(File.join(root, 'OpenGym/Resources/*')).sort.each { |p| app.resources_build_phase.add_file_reference(project.main_group.new_file(p.sub(root+'/', ''))) }
tests = project.new_target(:unit_test_bundle, 'OpenGymTests', :ios, '17.0')
tests.add_dependency(app)
tests.build_configurations.each do |c|
 c.build_settings.merge!({'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym.tests', 'SWIFT_VERSION'=>'5.0', 'GENERATE_INFOPLIST_FILE'=>'YES', 'TEST_HOST'=>'$(BUILT_PRODUCTS_DIR)/OpenGym.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/OpenGym', 'BUNDLE_LOADER'=>'$(TEST_HOST)'})
end
Dir.glob(File.join(root, 'OpenGymTests/*.swift')).sort.each { |p| tests.add_file_references([project.main_group.new_file(p.sub(root+'/', ''))]) }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.add_test_target(tests)
scheme.save_as(root+'/OpenGym.xcodeproj', 'OpenGym', true)
