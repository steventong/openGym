require 'xcodeproj'
require_relative 'shared-sources'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
app = project.targets.find { |t| t.name == 'OpenGYM' }
watch = project.targets.find { |t| t.name == 'OpenGYMWatch' } || project.new_target(:application, 'OpenGYMWatch', :watchos, '10.0')
watch.build_configurations.each do |c|
  c.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER'=>'me.itwl.opengym.watchkitapp', 'PRODUCT_NAME'=>'OpenGYMWatch',
    'SWIFT_VERSION'=>'5.0', 'SDKROOT'=>'watchos', 'SUPPORTED_PLATFORMS'=>'watchos watchsimulator',
    'WATCHOS_DEPLOYMENT_TARGET'=>'10.0', 'TARGETED_DEVICE_FAMILY'=>'4',
    'GENERATE_INFOPLIST_FILE'=>'YES', 'INFOPLIST_FILE'=>'Watch/Info.plist',
    'CODE_SIGN_ENTITLEMENTS'=>'Watch/OpenGYMWatch.entitlements', 'INFOPLIST_KEY_CFBundleDisplayName'=>'OpenGYM',
    'INFOPLIST_KEY_WKApplication'=>'YES', 'INFOPLIST_KEY_WKCompanionAppBundleIdentifier'=>'me.itwl.opengym',
    'INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp'=>'NO', 'INFOPLIST_KEY_WKWatchOnly'=>'NO',
    'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption'=>'NO', 'SKIP_INSTALL'=>'YES',
    'CODE_SIGN_STYLE'=>'Automatic', 'DEVELOPMENT_TEAM'=>app.build_configurations.first.build_settings['DEVELOPMENT_TEAM'],
    'MARKETING_VERSION'=>app.build_configurations.first.build_settings['MARKETING_VERSION'],
    'CURRENT_PROJECT_VERSION'=>app.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'],
    'ASSETCATALOG_COMPILER_APPICON_NAME'=>'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'=>'AccentColor'
  })
end

def add_source(project, target, relative)
  parts = relative.split('/'); filename = parts.pop
  group = parts.reduce(project.main_group) { |parent, dir| parent.groups.find { |g| g.path == dir } || parent.new_group(dir, dir) }
  file = group.files.find { |f| f.path == filename } || group.new_file(filename)
  target.add_file_references([file]) unless target.source_build_phase.files_references.include?(file)
end
Dir.glob(File.join(root, 'App/**/*.swift')).each do |path|
  add_source(project, app, path.delete_prefix(root + '/'))
end
SharedSources.register(project, root, targets: [app, watch])
Dir.glob(File.join(root, 'Watch/**/*.swift')).each { |p| add_source(project, watch, p.delete_prefix(root+'/')) }
tests = project.targets.find { |t| t.name == 'OpenGYMTests' }
Dir.glob(File.join(root, 'Tests/*.swift')).each { |p| add_source(project, tests, p.delete_prefix(root+'/')) }
resources_group = project.main_group.groups.find { |g| g.path == 'Resources' } || project.main_group.new_group('Resources', 'Resources')
shared_assets = resources_group.files.find { |f| f.path == 'Assets.xcassets' } || resources_group.new_file('Assets.xcassets')
[app, watch].each do |target|
  target.resources_build_phase.add_file_reference(shared_assets) unless target.resources_build_phase.files_references.any? { |file| file.uuid == shared_assets.uuid }
end
app.add_dependency(watch) unless app.dependencies.any? { |d| d.target == watch }
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Watch Content' } || app.new_copy_files_build_phase('Embed Watch Content')
embed.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'; embed.dst_subfolder_spec = '16'
file = embed.files.find { |f| f.file_ref == watch.product_reference } || embed.add_file_reference(watch.product_reference)
file.settings = { 'ATTRIBUTES'=>['RemoveHeadersOnCopy'] }
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch); scheme.set_launch_target(watch)
scheme.save_as(root+'/OpenGYM.xcodeproj', 'OpenGYMWatch', true)
