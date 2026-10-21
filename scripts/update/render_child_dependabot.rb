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
unless document.is_a?(Hash) && document.keys == %w[version updates] && document['version'] == 2 && document['updates'].is_a?(Array) && [1, 2].include?(document['updates'].length) && document['updates'].first['package-ecosystem'] == 'github-actions'
  abort 'Child Dependabot template must define one GitHub Actions update policy'
end
policy, npm_policy = document.fetch('updates')
if policy.key?('ignore')
  abort 'Foundation action ignores belong in the shared action catalog'
end
if policy.key?('groups')
  abort 'Child Dependabot groups belong in the npm additions entry'
end
# The optional second entry only carries npm groups. Templates without it,
# such as earlier vendored generations, render byte-identically so ownership
# recovery can reproduce them.
unless npm_policy.nil? || (npm_policy.keys == %w[package-ecosystem groups] && npm_policy['package-ecosystem'] == 'npm' &&
    npm_policy['groups'].is_a?(Hash) && !npm_policy['groups'].empty? &&
    npm_policy['groups'].all? { |name, group| name.is_a?(String) && group.is_a?(Hash) && group.keys == ['patterns'] && group['patterns'].is_a?(Array) && !group['patterns'].empty? && group['patterns'].all? { |pattern| pattern.is_a?(String) && !pattern.empty? } })
  abort 'Child Dependabot npm additions may only define dependency groups'
end
# Earlier generations ignored catalog actions. Projects now own their action
# pins (managed files keep project pin updates), so templates with npm additions
# (v1.10.10 and later) leave every action, including security updates, to
# Dependabot. Receiptless children only replay earlier templates, which keep
# their bytes.
ignores = npm_policy.nil? ? WPPluginBaseActionPins.catalog.keys.map { |name| name.split('/').first(2).join('/') }.uniq.sort : []
# Retain the authored common schedule and indentation. Only these two fixed
# scalars vary; action ignores never enter Composer or npm update blocks, and
# npm additions only enter npm update blocks.
lines = File.readlines(template)
header, entries = lines.first(2).join, lines.drop(2)
npm_start = entries.index("  - package-ecosystem: npm\n")
unless npm_start.nil? == npm_policy.nil?
  abort 'Unsupported child Dependabot template layout'
end
body = (npm_start ? entries.first(npm_start) : entries).join
npm_additions = npm_start ? entries.drop(npm_start + 1).join : ''
unless body.lines.include?("  - package-ecosystem: github-actions\n") && body.lines.include?("    directory: /\n")
  abort 'Unsupported child Dependabot template layout'
end
blocks = ecosystems.map do |ecosystem|
  package = ecosystem == 'admin-ui-npm' ? 'npm' : ecosystem
  directory = ecosystem == 'admin-ui-npm' ? '/.wp-plugin-base-admin-ui' : '/'
  update = body.sub('package-ecosystem: github-actions', "package-ecosystem: #{package}")
    .sub('directory: /', "directory: #{directory}")
  if ecosystem == 'github-actions' && !ignores.empty?
    update += "    ignore:\n" + ignores.map { |name| "      - dependency-name: #{name}\n" }.join
  end
  update += npm_additions if package == 'npm'
  update
end
output = header + blocks.join
# Text assembly must still yield exactly the selected policies.
rendered = begin
  Psych.safe_load(output, permitted_classes: [], permitted_symbols: [], aliases: false)
rescue Psych::Exception
  nil
end
expected = ecosystems.map { |ecosystem| ecosystem == 'admin-ui-npm' ? ['npm', '/.wp-plugin-base-admin-ui'] : [ecosystem, '/'] }
unless rendered.is_a?(Hash) && rendered.keys == %w[version updates] && rendered['updates'].is_a?(Array) &&
    rendered['updates'].map { |update| [update['package-ecosystem'], update['directory']] } == expected &&
    rendered['updates'].all? { |update| update['groups'] == (update['package-ecosystem'] == 'npm' && npm_policy ? npm_policy['groups'] : nil) } &&
    rendered['updates'].all? { |update| update['ignore'] == (update['package-ecosystem'] == 'github-actions' && !ignores.empty? ? ignores.map { |name| { 'dependency-name' => name } } : nil) }
  abort 'Rendered child Dependabot configuration does not match the selected policies'
end
puts output
