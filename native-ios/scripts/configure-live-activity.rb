require 'xcodeproj'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGym.xcodeproj'))
app = project.targets.find { |t| t.name == 'OpenGym' }
widget = project.targets.find { |t| t.name == 'OpenGymWidgets' } || project.new_target(:app_extension, 'OpenGymWidgets', :ios, '26.0')
widget.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'me.itwl.opengym.widgets',
    'IPHONEOS_DEPLOYMENT_TARGET' => '26.0',
    'SWIFT_VERSION' => '5.0', 'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_FILE' => 'OpenGymWidgets/Info.plist', 'INFOPLIST_KEY_CFBundleDisplayName' => 'openGym 训练',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'SKIP_INSTALL' => 'YES',
    'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => app.build_configurations.first.build_settings['DEVELOPMENT_TEAM'],
    'CURRENT_PROJECT_VERSION' => app.build_configurations.first.build_settings['CURRENT_PROJECT_VERSION'],
    'MARKETING_VERSION' => app.build_configurations.first.build_settings['MARKETING_VERSION'],
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) WORKOUT_WIDGET',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
  })
end

def activity_file(project, relative)
  parts = relative.split('/'); name = parts.pop
  group = parts.reduce(project.main_group) { |parent, dir| parent.groups.find { |g| g.path == dir } || parent.new_group(dir, dir) }
  group.files.find { |f| f.path == name } || group.new_file(name)
end

{app => ['OpenGym/**/*.swift', 'Shared/LiveActivity/*.swift', 'Shared/TrainingAction*.swift'], widget => ['OpenGymWidgets/*.swift', 'Shared/LiveActivity/*.swift', 'Shared/TrainingAction*.swift'],
 project.targets.find { |t| t.name == 'OpenGymTests' } => ['OpenGymTests/*.swift']}.each do |target, patterns|
  patterns.each do |pattern|
    Dir.glob(File.join(root, pattern)).sort.each do |path|
      file = activity_file(project, path.delete_prefix(root + '/'))
      target.add_file_references([file]) unless target.source_build_phase.files_references.include?(file)
    end
  end
end
activity_file(project, 'OpenGymWidgets/Info.plist')
app.add_dependency(widget) unless app.dependencies.any? { |d| d.target == widget }
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } || app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
file = embed.files.find { |f| f.file_ref == widget.product_reference } || embed.add_file_reference(widget.product_reference)
file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
project.save
