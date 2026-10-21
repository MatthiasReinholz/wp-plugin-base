#!/usr/bin/env ruby
# Edit only parsed action-reference scalars; preserve all other source bytes.
require 'pathname'
require_relative '../lib/action_pins'

begin
  root = File.realpath(ARGV.fetch(0))
  manifest = ARGV[1]
  policy = WPPluginBaseActionPins.catalog
  files = Dir.glob(File.join(root, '.github', 'workflows', '**', '*.{yml,yaml}')) +
    Dir.glob(File.join(root, '.github', 'actions', '**', 'action.{yml,yaml}'))
  updates = {}
  files.sort.each do |file|
    relative = Pathname.new(file).relative_path_from(Pathname.new(root)).to_s
    raise "Unsafe workflow path: #{relative}" if !WPPluginBaseActionPins.supported_path?(relative) || File.realpath(file) != file

    source, references = WPPluginBaseActionPins.references(file)
    updated = WPPluginBaseActionPins.rewrite_references(file, source, references) do |node|
      WPPluginBaseActionPins.replacement(node.value, policy, migrate: true)
    rescue StandardError => error
      raise "#{file}:#{node.start_line + 1}: #{error.message}"
    end
    updates[relative] = updated unless updated == source
  end
  # Validate every input before changing any file or publishing the staged-path manifest.
  updates.each { |relative, source| File.write(File.join(root, relative), source) }
  File.write(manifest, updates.keys.join("\n") + (updates.empty? ? '' : "\n")) unless manifest.to_s.empty?
  updates.each_key { |relative| puts "Migrated reviewed action pins: #{relative}" }
rescue StandardError => error
  warn(error.message)
  exit 1
end
