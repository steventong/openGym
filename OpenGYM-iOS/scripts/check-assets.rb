require 'json'
require 'set'
require 'xcodeproj'

# 同时检查当前工程与临时重新生成的工程，防止资源目录或 target 引用再次分叉。
root = File.expand_path(ARGV.first || File.join(__dir__, '..'))
project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
expected = File.join(root, 'Resources/Assets.xcassets')
catalogs = %w[App Watch Widgets Resources Shared].flat_map do |directory|
  Dir.glob(File.join(root, directory, '**/*.xcassets'))
end
raise "Expected one shared catalog, found #{catalogs}" unless catalogs == [expected]
references = project.files.select { |file| file.path&.end_with?('.xcassets') }
raise 'Expected one catalog reference in the project' unless references.length == 1 && references.first.real_path.to_s == expected

%w[OpenGYM OpenGYMWatch OpenGYMWidgets].each do |name|
  target = project.targets.find { |entry| entry.name == name }
  raise "Missing target: #{name}" unless target
  resources = target.resources_build_phase.files_references.select { |file| file.path&.end_with?('.xcassets') }
  raise "#{name} must reference only the shared catalog once" unless resources == references
  next if name == 'OpenGYMWidgets'
  target.build_configurations.each do |config|
    raise "#{name}/#{config.name}: wrong app icon" unless config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] == 'AppIcon'
    raise "#{name}/#{config.name}: wrong accent color" unless config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] == 'AccentColor'
  end
end

icons = JSON.parse(File.read(File.join(expected, 'AppIcon.appiconset/Contents.json')))['images']
idioms = icons.map { |image| image['idiom'] }.to_set
raise "Missing platform icon slots: #{idioms}" unless idioms == %w[iphone ipad ios-marketing watch watch-marketing].to_set
files = Dir.children(File.join(expected, 'AppIcon.appiconset')).to_set
raise 'Icon files do not match their slots' unless files == icons.map { |image| image['filename'] }.to_set.add('Contents.json')
colors = JSON.parse(File.read(File.join(expected, 'AccentColor.colorset/Contents.json')))['colors']
raise 'Expected one default accent and one Watch variant' unless colors.map { |color| color['idiom'] }.sort == %w[universal watch]
puts 'Shared catalog, three target memberships, platform icon slots and accent variants verified.'
