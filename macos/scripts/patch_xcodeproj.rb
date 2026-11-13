#!/usr/bin/env ruby
# Idempotently wires the embedded-Python pieces into macos/Runner.xcodeproj. The Swift
# sources and the Python code are shared with iOS (../ios/Runner, ../ios/PythonApp).
#
#   ruby macos/scripts/patch_xcodeproj.rb     (needs macos/Python.xcframework)
require 'xcodeproj'

macos_dir = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(macos_dir, 'Runner.xcodeproj'))
target  = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')

shared = project.main_group.find_subpath('Shared (iOS)', true)
shared.set_source_tree('SOURCE_ROOT')
%w[PythonRuntime.swift JSSolver.swift ExtractorChannel.swift VideoMuxer.swift].each do |name|
  path = "../ios/Runner/#{name}"
  next if shared.files.any? { |f| f.path == path }
  ref = shared.new_file(path)
  target.source_build_phase.add_file_reference(ref)
  puts "added source #{name}"
end

fw = project.main_group.files.find { |f| f.path == 'Python.xcframework' } ||
     project.main_group.new_file('Python.xcframework')
fw.last_known_file_type = 'wrapper.xcframework'
unless target.frameworks_build_phase.files_references.include?(fw)
  target.frameworks_build_phase.add_file_reference(fw, true)
  puts 'linked Python.xcframework'
end

embed = target.copy_files_build_phases.find { |p| p.symbol_dst_subfolder_spec == :frameworks }
if embed.nil?
  embed = target.new_copy_files_build_phase('Embed Frameworks')
  embed.symbol_dst_subfolder_spec = :frameworks
end
unless embed.files_references.include?(fw)
  build_file = embed.add_file_reference(fw, true)
  build_file.settings = { 'ATTRIBUTES' => %w[CodeSignOnCopy RemoveHeadersOnCopy] }
  puts 'embedded Python.xcframework'
end

%w[app app_packages].each do |dir|
  path = "../ios/PythonApp/#{dir}"
  ref = shared.files.find { |f| f.path == path }
  unless ref
    ref = shared.new_file(path)
    ref.last_known_file_type = 'folder'
    puts "added folder reference #{path}"
  end
  unless target.resources_build_phase.files_references.include?(ref)
    target.resources_build_phase.add_file_reference(ref)
  end
end

bridging = 'Runner/Runner-Bridging-Header.h'
runner_group = project.main_group['Runner']
runner_group.new_file('Runner-Bridging-Header.h') unless runner_group.files.any? { |f| f.path == 'Runner-Bridging-Header.h' }
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = bridging
end

project.save
puts 'macos/Runner.xcodeproj updated.'
