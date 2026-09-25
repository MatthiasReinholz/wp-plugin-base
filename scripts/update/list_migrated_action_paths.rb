#!/usr/bin/env ruby
require_relative '../lib/action_pins'

begin
  root = File.realpath(ARGV.fetch(0))
  manifest = ARGV.fetch(1)
  paths = File.readlines(manifest, chomp: true).reject(&:empty?).uniq
  paths.each do |path|
    unless WPPluginBaseActionPins.supported_path?(path) && path.match?(%r{\A\.github/(?:workflows/(?:[^/,\r\n]+/)*[^/,\r\n]+\.ya?ml|actions/(?:[^/,\r\n]+/)+action\.ya?ml)\z}) && !path.split('/').include?('..')
      raise "Invalid migrated action staging path: #{path}"
    end
    absolute = File.join(root, path)
    raise "Unsafe migrated action staging path: #{path}" unless File.realpath(absolute) == absolute
    WPPluginBaseActionPins.audit([absolute])
  end
  puts paths unless paths.empty?
rescue StandardError => error
  warn(error.message)
  exit 1
end
