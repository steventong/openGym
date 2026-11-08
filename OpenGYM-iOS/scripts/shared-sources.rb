require 'xcodeproj'

# Shared 的职责目录与平台功能目录共同决定 target；生成脚本统一使用此规则。
module SharedSources
  def self.target_names(relative)
    directories = relative.split('/')[0...-1]
    unless directories.first == 'Shared' && %w[Models Services ViewModels Views].include?(directories[1])
      raise ArgumentError, "Shared Swift sources must be grouped by responsibility: #{relative}"
    end
    if directories.include?('Watch') || directories.include?('Health')
      %w[OpenGYM OpenGYMWatch]
    elsif directories.include?('LiveActivity')
      %w[OpenGYM OpenGYMWidgets]
    else
      %w[OpenGYM OpenGYMWatch OpenGYMWidgets]
    end
  end

  def self.reference(project, relative)
    parts = relative.split('/')
    filename = parts.pop
    group = parts.reduce(project.main_group) do |parent, directory|
      parent.groups.find { |child| child.path == directory } || parent.new_group(directory, directory)
    end
    group.files.find { |file| file.path == filename } || group.new_file(filename)
  end

  def self.register(project, root, targets:)
    Dir.glob(File.join(root, 'Shared/**/*.swift')).sort.each do |path|
      relative = path.delete_prefix(root + '/')
      file = reference(project, relative)
      names = target_names(relative)
      targets.each do |target|
        if names.include?(target.name)
          target.add_file_references([file]) unless target.source_build_phase.files_references.include?(file)
        else
          target.source_build_phase.files.select { |entry| entry.file_ref == file }.each(&:remove_from_project)
        end
      end
    end
  end
end
