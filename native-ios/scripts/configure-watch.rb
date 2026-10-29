require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGym.xcodeproj'))
app = project.targets.find { |t| t.name == 'OpenGym' }
watch = project.targets.find { |t| t.name == 'OpenGymWatch' } || project.new_target(:application, 'OpenGymWatch', :watchos, '10.0')
watch.build_configurations.each do |c|
  c.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym.watchkitapp', 'PRODUCT_NAME'=>'OpenGymWatch',
    'SWIFT_VERSION'=>'5.0', 'SDKROOT'=>'watchos', 'SUPPORTED_PLATFORMS'=>'watchos watchsimulator',
    'WATCHOS_DEPLOYMENT_TARGET'=>'10.0', 'TARGETED_DEVICE_FAMILY'=>'4',
    'GENERATE_INFOPLIST_FILE'=>'YES', 'INFOPLIST_KEY_CFBundleDisplayName'=>'openGym',
    'INFOPLIST_KEY_WKApplication'=>'YES', 'INFOPLIST_KEY_WKCompanionAppBundleIdentifier'=>'me.itwl.opengym',
    'INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp'=>'NO', 'INFOPLIST_KEY_WKWatchOnly'=>'NO',
    'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'=>'NO', 'SKIP_INSTALL'=>'YES',
    'CODE_SIGN_STYLE'=>'Automatic', 'DEVELOPMENT_TEAM'=>app.build_configurations.first.build_settings['DEVELOPMENT_TEAM'],
    'MARKETING_VERSION'=>app.build_configurations.first.build_settings['MARKETING_VERSION'],
    'CURRENT_PROJECT_VERSION'=>app.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'],
    'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon'
  })
end

def add_source(project, target, relative)
  parts = relative.split('/'); filename = parts.pop
  group = parts.reduce(project.main_group) { |parent, dir| parent.groups.find { |g| g.path == dir } || parent.new_group(dir, dir) }
  file = group.files.find { |f| f.path == filename } || group.new_file(filename)
  target.add_file_references([file]) unless target.source_build_phase.files_references.include?(file)
end
Dir.glob(File.join(root, 'OpenGym/**/*.swift')).each { |p| add_source(project, app, p.delete_prefix(root+'/')) }
Dir.glob(File.join(root, 'Shared/*.swift')).each { |p| [app, watch].each { |t| add_source(project, t, p.delete_prefix(root+'/')) } }
Dir.glob(File.join(root, 'OpenGymWatch/*.swift')).each { |p| add_source(project, watch, p.delete_prefix(root+'/')) }
tests = project.targets.find { |t| t.name == 'OpenGymTests' }
Dir.glob(File.join(root, 'OpenGymTests/*.swift')).each { |p| add_source(project, tests, p.delete_prefix(root+'/')) }
watch_group = project.main_group.groups.find { |g| g.path == 'OpenGymWatch' }
assets = watch_group.files.find { |f| f.path == 'Assets.xcassets' } || watch_group.new_file('Assets.xcassets')
watch.resources_build_phase.add_file_reference(assets) unless watch.resources_build_phase.files_references.include?(assets)
app.add_dependency(watch) unless app.dependencies.any? { |d| d.target == watch }
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' } || app.new_copy_files_build_phase('Embed Watch Content')
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'; embed.dst_subfolder_spec = '16'
file = embed.files.find { |f| f.file_ref == watch.product_reference } || embed.add_file_reference(watch.product_reference)
file.settings = { 'ATTRIBUTES'=>['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch); scheme.set_launch_target(watch)
scheme.save_as(root+'/OpenGym.xcodeproj', 'OpenGymWatch', true)
