#!/usr/bin/env ruby
require_relative '../lib/action_pins'

template, root, admin_enabled, selection = ARGV
selection ||= 'auto'
ecosystems = selection.split(',')
if selection == 'auto'
  ecosystems = ['github-actions']
  ecosystems << 'composer' if File.file?(File.join(root, 'composer.json'))
  ecosystems << 'npm' if File.file?(File.join(root, 'package.json'))
  if admin_enabled == 'true' || File.file?(File.join(root, '.wp-plugin-base-admin-ui', 'package.json'))
    ecosystems << 'admin-ui-npm'
  end
end
allowed = %w[github-actions composer npm admin-ui-npm]
unless !ecosystems.empty? && ecosystems.uniq == ecosystems && (ecosystems - allowed).empty?
  abort 'Invalid child Dependabot ecosystem selection'
end

document = Psych.safe_load(File.read(template), permitted_classes: [], permitted_symbols: [], aliases: false)
unless document.is_a?(Hash) && document['version'] == 2 && document['updates'].is_a?(Array) && document['updates'].length == 1 && document['updates'].first['package-ecosystem'] == 'github-actions'
  abort 'Child Dependabot template must define one GitHub Actions update policy'
end
policy = document.fetch('updates').first
if policy.key?('ignore')
  abort 'Foundation action ignores belong in the shared action catalog'
end
ignores = WPPluginBaseActionPins.catalog.keys.map { |name| name.split('/').first(2).join('/') }.uniq.sort
# Retain the authored common schedule and indentation. Only these two fixed
# scalars vary; action ignores never enter Composer or npm update blocks.
header, body = File.readlines(template).first(2).join, File.readlines(template).drop(2).join
unless body.lines.include?("  - package-ecosystem: github-actions\n") && body.lines.include?("    directory: /\n")
  abort 'Unsupported child Dependabot template layout'
end
blocks = ecosystems.map do |ecosystem|
  package = ecosystem == 'admin-ui-npm' ? 'npm' : ecosystem
  directory = ecosystem == 'admin-ui-npm' ? '/.wp-plugin-base-admin-ui' : '/'
  update = body.sub('package-ecosystem: github-actions', "package-ecosystem: #{package}")
    .sub('directory: /', "directory: #{directory}")
  if ecosystem == 'github-actions'
    update += "    ignore:\n" + ignores.map { |name| "      - dependency-name: #{name}\n" }.join
  end
  update
end
puts header + blocks.join
