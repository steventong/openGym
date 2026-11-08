require 'xcodeproj'
require_relative 'shared-sources'
root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
SharedSources.register(project, root,
    targets: project.targets.select { |target| %w[OpenGYM OpenGYMWatch OpenGYMWidgets].include?(target.name) })
# 移除旧 JSON 和手工 strings 的引用，避免与 String Catalog 编译产物冲突。
old_groups = project.main_group.groups.select { |g| g.path == '../localization' || g.path&.start_with?('Localization/') }
old_groups.each do |group|
  group.recursive_children.each do |ref|
    project.targets.each { |t| t.resources_build_phase.files.select { |f| f.file_ref == ref }.each(&:remove_from_project) }
  end
  group.remove_from_project
end
resources_group = project.main_group.groups.find { |g| g.path == 'Resources' } || project.main_group.new_group('Resources', 'Resources')
group = resources_group.groups.find { |g| g.path == 'Localization' } || resources_group.new_group('Localization', 'Localization')
catalogs = %w[Localizable Vocabulary Muscles].map do |name|
  file = group.files.find { |f| f.path == "#{name}.xcstrings" } || group.new_file("#{name}.xcstrings")
  file.last_known_file_type = 'text.json.xcstrings'
  file
end
project.targets.select { |t| %w[OpenGYM OpenGYMWatch OpenGYMWidgets].include?(t.name) }.each do |target|
  resources = catalogs.dup
  unless target.name == 'OpenGYMWidgets'
    native_group = group.groups.find { |g| g.path == target.name } || group.new_group(target.name, target.name)
    info = native_group.files.find { |f| f.path == 'InfoPlist.xcstrings' } || native_group.new_file('InfoPlist.xcstrings')
    info.last_known_file_type = 'text.json.xcstrings'
    resources << info
  end
  resources.each { |ref| target.resources_build_phase.add_file_reference(ref) unless target.resources_build_phase.files_references.include?(ref) }
  target.build_configurations.each do |config|
    config.build_settings['INFOPLIST_KEY_CFBundleLocalizations'] = ['en', 'zh-Hans']
    config.build_settings['LOCALIZATION_PREFERS_STRING_CATALOGS'] = 'YES'
  end
end
project.root_object.known_regions = ['en', 'zh-Hans', 'Base']
project.save
