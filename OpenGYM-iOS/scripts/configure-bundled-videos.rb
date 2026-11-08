require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
app = project.targets.find { |target| target.name == 'OpenGYM' }
# Exercise images and videos download on demand; only icons and branding are bundled.
project.files.select { |file| ['../catalogue/media/clip', '../catalogue/media/still', '../catalogue/media/thumbnails'].include?(file.path) }.each(&:remove_from_project)
service = project.main_group.find_subpath('App/Services', false)
%w[ExerciseVideoCache.swift ExerciseImageCache.swift].each do |name|
  file = service.files.find { |reference| reference.path == name } || service.new_file(name)
  app.add_file_references([file]) unless app.source_build_phase.files_references.include?(file)
end
# Real media fixtures belong only to the test bundle, never the app.
tests = project.targets.find { |target| target.name == 'OpenGYMTests' }
%w[../catalogue/media/clip/0289.mp4 ../catalogue/media/thumbnails/0289.webp].each do |path|
  fixture = project.files.find { |file| file.path == path } || project.main_group.find_subpath('Tests', false).new_file(path, 'SOURCE_ROOT')
  tests.resources_build_phase.add_file_reference(fixture, true)
end
project.save
