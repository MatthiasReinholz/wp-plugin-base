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
    lines = source.lines
    offsets = [0]
    lines.each { |line| offsets << offsets.last + line.length }
    replacements = []
    references.each do |node|
      begin
        replacement = WPPluginBaseActionPins.replacement(node.value, policy, migrate: true)
      rescue StandardError => error
        raise "#{file}:#{node.start_line + 1}: #{error.message}"
      end
      next if replacement == node.value
      raise "#{file}:#{node.start_line + 1}: multiline action references require manual review" unless node.start_line == node.end_line

      start = offsets[node.start_line] + node.start_column
      finish = offsets[node.end_line] + node.end_column
      token = source[start...finish]
      unless [node.value, "'#{node.value}'", "\"#{node.value}\""].include?(token)
        raise "#{file}:#{node.start_line + 1}: unsupported action scalar syntax requires manual review"
      end
      replacements << [start, finish, token.sub(node.value, replacement)]
    end
    replacements.sort_by(&:first).reverse_each { |start, finish, replacement| source[start...finish] = replacement }
    updates[relative] = source unless replacements.empty?
  end
  # Validate every input before changing any file or publishing the staged-path manifest.
  updates.each { |relative, source| File.write(File.join(root, relative), source) }
  File.write(manifest, updates.keys.join("\n") + (updates.empty? ? '' : "\n")) unless manifest.to_s.empty?
  updates.each_key { |relative| puts "Migrated reviewed action pins: #{relative}" }
rescue StandardError => error
  warn(error.message)
  exit 1
end
