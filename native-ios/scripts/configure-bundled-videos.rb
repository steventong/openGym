require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'OpenGym.xcodeproj'))
app = project.targets.find { |target| target.name == 'OpenGym' }
resources = project.main_group.find_subpath('OpenGym/Resources', false)
# Folder resources copy tracked media without duplicating source files.
%w[clip still].each do |folder|
  path = "../catalogue/media/#{folder}"
  reference = project.files.find { |file| file.path == path } || resources.new_file(path, 'SOURCE_ROOT')
  reference.last_known_file_type = 'folder'
  app.resources_build_phase.add_file_reference(reference, true)
end
project.save
