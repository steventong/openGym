require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGym.xcodeproj'))
app = project.targets.find { |target| target.name == 'OpenGym' }
resources = project.main_group.find_subpath('OpenGym/Resources', false)
# Videos download on demand; thumbnails are compiled from Assets.xcassets.
project.files.select { |file| ['../catalogue/media/clip', '../catalogue/media/still', '../catalogue/media/thumbnails'].include?(file.path) }.each(&:remove_from_project)
service = project.main_group.find_subpath('OpenGym/Services', false)
unless service.files.any? { |file| file.path == 'ExerciseVideoCache.swift' }
  app.add_file_references([service.new_file('ExerciseVideoCache.swift')])
end
# A single real clip belongs only to the test bundle for download/playability tests.
tests = project.targets.find { |target| target.name == 'OpenGymTests' }
fixture_path = '../catalogue/media/clip/0289.mp4'
fixture = project.files.find { |file| file.path == fixture_path } || project.main_group.find_subpath('OpenGymTests', false).new_file(fixture_path, 'SOURCE_ROOT')
tests.resources_build_phase.add_file_reference(fixture, true)
project.save
