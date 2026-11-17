require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGYM.xcodeproj'))
app = project.targets.find { |target| target.name == 'OpenGYM' }
# Exercise images and videos download on demand; only icons and branding are bundled.
service = project.main_group.find_subpath('App/Services', false)
%w[ExerciseVideoCache.swift ExerciseImageCache.swift].each do |name|
  file = service.files.find { |reference| reference.path == name } || service.new_file(name)
  app.add_file_references([file]) unless app.source_build_phase.files_references.include?(file)
end
# Media fixtures live in Tests/Fixtures and belong only to the test bundle, never the app.
tests = project.targets.find { |target| target.name == 'OpenGYMTests' }
fixtures = project.main_group.find_subpath('Tests/Fixtures', true)
fixtures.set_source_tree('<group>'); fixtures.set_path('Fixtures')
%w[0289.mp4 0289.webp].each do |name|
  fixture = fixtures.files.find { |file| file.path == name } || fixtures.new_file(name)
  tests.resources_build_phase.add_file_reference(fixture, true)
end
project.save
