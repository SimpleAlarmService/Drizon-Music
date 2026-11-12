#!/usr/bin/env ruby
# Idempotently wires the embedded-Python pieces into ios/Runner.xcodeproj:
#   * Swift sources (PythonRuntime / JSSolver / ExtractorChannel)
#   * Python.xcframework (linked + embedded & signed)
#   * PythonApp/app and PythonApp/app_packages as bundle folder references
#   * "Install Python" build phase (copies stdlib, turns .so modules into frameworks)
#
# Needs the `xcodeproj` gem (installed with CocoaPods, so any Flutter iOS setup has it).
require 'xcodeproj'

ios_dir = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(ios_dir, 'Runner.xcodeproj'))
target  = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
runner_group = project.main_group['Runner'] or abort('Runner group not found')

# 1. Swift sources ----------------------------------------------------------
%w[PythonRuntime.swift JSSolver.swift ExtractorChannel.swift].each do |name|
  next if runner_group.files.any? { |f| f.path == name }
  ref = runner_group.new_file(name)
  target.source_build_phase.add_file_reference(ref)
  puts "added source #{name}"
end

# 2. Python.xcframework -------------------------------------------------------
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

# 3. Python code + packages as folder references ----------------------------
%w[PythonApp/app PythonApp/app_packages].each do |dir|
  ref = project.main_group.files.find { |f| f.path == dir }
  unless ref
    ref = project.main_group.new_file(dir)
    ref.last_known_file_type = 'folder'
    puts "added folder reference #{dir}"
  end
  unless target.resources_build_phase.files_references.include?(ref)
    target.resources_build_phase.add_file_reference(ref)
  end
end

# 4. "Install Python" phase, placed before framework embedding/signing -------
phase_name = 'Install Python'
unless target.shell_script_build_phases.any? { |p| p.name == phase_name }
  phase = target.new_shell_script_build_phase(phase_name)
  phase.shell_script = <<~SH
    set -e
    source "$PROJECT_DIR/Python.xcframework/build/utils.sh"
    install_python Python.xcframework app app_packages
  SH
  phase.always_out_of_date = '1'
  target.build_phases.delete(phase)
  target.build_phases.insert(target.build_phases.index(embed), phase)
  puts "added build phase '#{phase_name}'"
end

# 5. Build settings ------------------------------------------------------------
target.build_configurations.each do |config|
  config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO' # script reads the project dir
  config.build_settings['ENABLE_BITCODE'] = 'NO'
end

project.save
puts 'Runner.xcodeproj updated.'
