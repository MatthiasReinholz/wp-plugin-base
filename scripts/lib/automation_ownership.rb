#!/usr/bin/env ruby
# frozen_string_literal: true

# Resolve profile transitions before sync writes any project file. Only recorded
# bytes (or byte-identical legacy templates) establish automation ownership.
# Projects may update action pins in managed files; every other byte stays owned.
require 'json'
require 'digest'
require 'fileutils'
require_relative 'action_pins'

module AutomationOwnership
  module_function

  def hosted?(name)
    name.start_with?('.github/', '.gitlab/') || name == '.gitlab-ci.yml'
  end

  def regular_path(root, name)
    unless hosted?(name) && name.split('/').none? { |part| ['', '.', '..'].include?(part) } && name !~ /[\x00-\x1f\x7f\\]/
      raise "Invalid automation ownership path: #{name.inspect}"
    end
    path = root
    name.split('/').each do |part|
      path = File.join(path, part)
      raise "Automation ownership path must not use symlinks: #{name}" if File.symlink?(path)
    end
    raise "Automation path is not a regular file: #{name}" if File.exist?(path) && !File.file?(path)

    path
  end

  def hashes(file)
    File.readlines(file, chomp: true).each_with_object({}) do |line, result|
      digest, name = line.split("\t", 2)
      raise 'Invalid rendered automation inventory.' unless digest&.match?(/\A[0-9a-f]{64}\z/) && name

      result[name] = digest
    end
  end

  DIGEST = /\A[0-9a-f]{64}\z/
  NEUTRAL_PIN = '0' * 40

  def pinned_references(path)
    source, references = WPPluginBaseActionPins.references(path)
    pins = references.reject { |node| node.value.start_with?('./') }
    return nil unless pins.all? { |node| WPPluginBaseActionPins::PINNED_REFERENCE.match?(node.value) }

    [source, pins]
  rescue StandardError
    nil
  end

  def action_name(node)
    WPPluginBaseActionPins::PINNED_REFERENCE.match(node.value)[1]
  end

  # The file's bytes with each action pinned to `choice[name]`, or to a neutral
  # pin when no choice is given.
  def with_pins(path, source, pins, choice = nil)
    WPPluginBaseActionPins.rewrite_references(path, source, pins) do |node|
      "#{action_name(node)}@#{choice ? choice.fetch(action_name(node)) : NEUTRAL_PIN}"
    end
  end

  def pin_neutral_digest(path)
    source, pins = pinned_references(path)
    source && Digest::SHA256.hexdigest(with_pins(path, source, pins))
  rescue StandardError
    nil
  end

  # True when the file equals the synchronized bytes behind `digest` except for
  # full-SHA action pins, such as a project's Dependabot update. Receipts that
  # predate pin-neutral digests are matched by trying the catalog's reviewed
  # pins, which include every pin earlier generations rendered.
  def pin_only_change?(path, digest, neutral_digest = nil)
    source, pins = pinned_references(path)
    return false if source.nil? || pins.empty?
    return Digest::SHA256.hexdigest(with_pins(path, source, pins)) == neutral_digest if neutral_digest

    catalog = WPPluginBaseActionPins.catalog
    names = pins.map { |node| action_name(node) }.uniq
    candidates = names.map { |name| catalog.key?(name) ? [catalog[name]['current'], *catalog[name]['predecessors']] : [] }
    return false if candidates.any?(&:empty?) || candidates.map(&:length).inject(1, :*) > 4096

    candidates.first.product(*candidates.drop(1)).any? do |combination|
      Digest::SHA256.hexdigest(with_pins(path, source, pins, names.zip(combination).to_h)) == digest
    end
  rescue StandardError
    false
  end

  # Pins to carry into the next generation, per action and in file order. A pin
  # the catalog reviewed (current or an older predecessor) is nil, so the newly
  # rendered pin applies; any other full SHA is the project's and is kept, so
  # sync never downgrades a project pin.
  def project_pins(path)
    # Files without parseable action references (such as .gitlab-ci.yml, which
    # uses YAML anchors) carry no project pins.
    _source, pins = pinned_references(path)
    return {} if pins.nil?

    catalog = WPPluginBaseActionPins.catalog
    kept = pins.group_by { |node| action_name(node) }.to_h do |name, nodes|
      reviewed = catalog.key?(name) ? [catalog[name]['current'], *catalog[name]['predecessors']] : []
      [name, nodes.map { |node| pin = node.value.split('@', 2).last; reviewed.include?(pin) ? nil : pin }]
    end
    kept.reject { |_name, values| values.compact.empty? }
  end

  # Reapply project pins to a newly rendered file. One project pin per action
  # applies to every occurrence; differing pins apply by position when the
  # occurrence count is unchanged. Returns the actions it could not map.
  def reapply_project_pins(path, kept)
    source, references = pinned_references(path)
    raise "Automation changed during sync: #{path}" unless source

    occurrences = references.group_by { |node| action_name(node) }
    unmapped = []
    choice = {}
    kept.each do |name, values|
      nodes = occurrences.fetch(name, [])
      next if nodes.empty?

      pins = values.compact.uniq
      if pins.length == 1
        nodes.each { |node| choice[node] = pins.first }
      elsif values.length == nodes.length
        nodes.zip(values).each { |node, pin| choice[node] = pin if pin }
      else
        unmapped << name
      end
    end
    File.write(path, WPPluginBaseActionPins.rewrite_references(path, source, references) { |node| choice.key?(node) ? "#{action_name(node)}@#{choice[node]}" : node.value })
    [choice.values.uniq.length, unmapped]
  end

  def validate(root, expected_profile, expected_paths)
    root = File.realpath(root)
    receipt = File.join(root, '.wp-plugin-base-automation.json')
    raise 'Automation ownership state must be a regular file, not a symlink.' if File.symlink?(receipt) || !File.file?(receipt)

    data = JSON.parse(File.read(receipt))
    unless data.is_a?(Hash) && data['schema_version'] == 1 && data['profile'] == expected_profile && data['files'].is_a?(Hash)
      raise 'Automation profile changed or ownership receipt is invalid. Run managed sync before validation.'
    end
    paths = expected_paths.lines.map(&:chomp).select { |name| hosted?(name) }.sort
    unless data['files'].keys.sort == paths
      raise 'Automation ownership differs from the configured profile. Run managed sync before validation.'
    end
    neutral = data.fetch('pin_neutral', {})
    unless neutral.is_a?(Hash) && neutral.all? { |name, digest| data['files'].key?(name) && digest.is_a?(String) && digest.match?(DIGEST) }
      raise 'Automation ownership receipt is invalid. Run managed sync before validation.'
    end
    data['files'].each do |name, digest|
      path = regular_path(root, name)
      unless digest.is_a?(String) && digest.match?(DIGEST) && File.file?(path)
        raise "Managed automation differs from its synchronized receipt: #{name}"
      end
      next if Digest::SHA256.file(path).hexdigest == digest

      if pin_only_change?(path, digest, neutral[name])
        puts "Managed automation keeps project-updated action pins: #{name}"
        next
      end
      raise "Managed automation differs from its synchronized receipt: #{name}. wp-plugin-base generates this file; " \
            'only full-SHA action pin updates may differ. Move other edits into an application-owned workflow, then ' \
            "restore the synchronized bytes with `git checkout \"$(git log -1 --format=%H -- .wp-plugin-base-automation.json)\" -- '#{name}'` " \
            'in a full-history clone.'
    end
  end

  def run(root, desired_file, legacy_file, mode)
    root = File.realpath(root)
    state_path = File.join(root, '.wp-plugin-base-automation.json')
    raise 'Automation ownership state must not be a symlink.' if File.symlink?(state_path)
    desired = hashes(desired_file)
    legacy = hashes(legacy_file)
    previous = {}
    previous_neutral = {}
    prior_state_path = state_path
    if !File.exist?(prior_state_path) && ENV['WP_PLUGIN_BASE_PRIOR_AUTOMATION_RECEIPT']
      prior_state_path = ENV.fetch('WP_PLUGIN_BASE_PRIOR_AUTOMATION_RECEIPT')
    end
    if File.exist?(prior_state_path)
      state = JSON.parse(File.read(prior_state_path))
      unless state.is_a?(Hash) && state['schema_version'] == 1 && %w[managed local].include?(state['profile']) && state['files'].is_a?(Hash)
        raise 'Invalid automation ownership state; restore the last reviewed state before sync.'
      end
      previous = state['files']
      previous_neutral = state.fetch('pin_neutral', {})
      raise 'Invalid automation ownership digest.' unless previous_neutral.is_a?(Hash)

      [previous, previous_neutral].each do |digests|
        digests.each do |name, digest|
          regular_path(root, name)
          raise 'Invalid automation ownership digest.' unless digest.is_a?(String) && digest.match?(DIGEST)
        end
      end
    else
      legacy.each do |name, digest|
        path = regular_path(root, name)
        previous[name] = digest if File.file?(path) && (Digest::SHA256.file(path).hexdigest == digest || pin_only_change?(path, digest))
      end
    end
    removals = []
    kept_pins = {}
    (previous.keys | desired.keys).each do |name|
      path = regular_path(root, name)
      actual = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
      if previous.key?(name) && actual && actual != previous[name] && actual != desired[name] &&
          !pin_only_change?(path, previous[name], previous_neutral[name])
        raise "Managed automation was edited: #{name}. Preserve the edit in an application-owned file, then restore the last synchronized bytes or remove this path before retrying. Action pin updates are kept automatically; any other change is not. No sync changes were made."
      end
      # Project pins persist across every later sync, not only the one after the
      # change: the receipt records the pinned bytes as synchronized.
      if previous.key?(name) && desired.key?(name) && actual && actual != desired[name]
        pins = project_pins(path)
        kept_pins[name] = pins unless pins.empty?
      end
      if desired.key?(name) && actual && !previous.key?(name) && actual != desired[name]
        raise "Application-owned automation conflicts with managed output: #{name}. Move or explicitly remove that file before enabling managed automation. No sync changes were made."
      end
      removals << name if previous.key?(name) && !desired.key?(name) && actual
    end
    # Sync overwrites managed files between the two phases, so the check phase
    # records the project pins that the write phase reapplies.
    kept_pins_path = File.join(File.dirname(File.realpath(desired_file)), 'project-action-pins.json')
    if mode == 'check'
      File.write(kept_pins_path, JSON.generate(kept_pins))
      puts removals
      return
    end
    kept_pins = File.file?(kept_pins_path) ? JSON.parse(File.read(kept_pins_path)) : {}
    # The caller has already written and checked the exact desired generation.
    # Capture leaves files in place, so pin-only differences are accepted there.
    files = {}
    neutral = {}
    desired.each do |name, digest|
      path = regular_path(root, name)
      raise "Automation changed during sync: #{name}" unless File.file?(path)

      if Digest::SHA256.file(path).hexdigest == digest
        pins = kept_pins.fetch(name, {})
        unless pins.empty?
          applied, unmapped = reapply_project_pins(path, pins)
          puts "Kept project action pins in #{name}" if applied.positive?
          unmapped.each { |action| warn "Warning: #{name} uses several project pins for #{action}, and the new generation changed its occurrences; review the rendered #{action} pins." }
        end
      elsif !pin_only_change?(path, digest)
        raise "Automation changed during sync: #{name}"
      end
      files[name] = Digest::SHA256.file(path).hexdigest
      neutral_digest = pin_neutral_digest(path)
      neutral[name] = neutral_digest if neutral_digest
    end
    temporary = state_path + ".tmp-#{Process.pid}"
    begin
      File.open(temporary, 'wx', 0o644) do |file|
        file.write(JSON.pretty_generate({ 'schema_version' => 1, 'profile' => ENV.fetch('AUTOMATION_PROFILE', 'managed'), 'files' => files.sort.to_h, 'pin_neutral' => neutral.sort.to_h }) + "\n")
      end
      File.rename(temporary, state_path)
    ensure
      File.unlink(temporary) if File.exist?(temporary)
    end
  end
end

begin
  if ARGV[0] == 'validate'
    AutomationOwnership.validate(ARGV[1], ARGV[2], ENV.fetch('WP_PLUGIN_BASE_ACTIVE_MANAGED_PATHS'))
  else
    AutomationOwnership.run(*ARGV)
  end
rescue StandardError => e
  warn e.message
  exit 1
end
