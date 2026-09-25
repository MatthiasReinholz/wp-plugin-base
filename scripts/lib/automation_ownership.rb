#!/usr/bin/env ruby
# frozen_string_literal: true

# Resolve profile transitions before sync writes any project file. Only recorded
# bytes (or byte-identical legacy templates) establish automation ownership.
require 'json'
require 'digest'
require 'fileutils'

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
    data['files'].each do |name, digest|
      path = regular_path(root, name)
      unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/) && File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
        raise "Managed automation differs from its synchronized receipt: #{name}"
      end
    end
  end

  def run(root, desired_file, legacy_file, mode)
    root = File.realpath(root)
    state_path = File.join(root, '.wp-plugin-base-automation.json')
    raise 'Automation ownership state must not be a symlink.' if File.symlink?(state_path)
    desired = hashes(desired_file)
    legacy = hashes(legacy_file)
    previous = {}
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
      previous.each do |name, digest|
        regular_path(root, name)
        raise 'Invalid automation ownership digest.' unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      end
    else
      legacy.each do |name, digest|
        path = regular_path(root, name)
        previous[name] = digest if File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
      end
    end
    removals = []
    (previous.keys | desired.keys).each do |name|
      path = regular_path(root, name)
      actual = File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil
      if previous.key?(name) && actual && actual != previous[name] && actual != desired[name]
        raise "Managed automation was edited: #{name}. Preserve the edit in an application-owned file, then restore the last synchronized bytes or remove this path before retrying. No sync changes were made."
      end
      if desired.key?(name) && actual && !previous.key?(name) && actual != desired[name]
        raise "Application-owned automation conflicts with managed output: #{name}. Move or explicitly remove that file before enabling managed automation. No sync changes were made."
      end
      removals << name if previous.key?(name) && !desired.key?(name) && actual
    end
    if mode == 'check'
      puts removals
      return
    end
    # The caller has already written and checked the exact desired generation.
    desired.each do |name, digest|
      path = regular_path(root, name)
      raise "Automation changed during sync: #{name}" unless File.file?(path) && Digest::SHA256.file(path).hexdigest == digest
    end
    temporary = state_path + ".tmp-#{Process.pid}"
    begin
      File.open(temporary, 'wx', 0o644) do |file|
        file.write(JSON.pretty_generate({ 'schema_version' => 1, 'profile' => ENV.fetch('AUTOMATION_PROFILE', 'managed'), 'files' => desired.sort.to_h }) + "\n")
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
