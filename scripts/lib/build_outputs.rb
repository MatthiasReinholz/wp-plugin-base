#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'pathname'
require 'fileutils'

module BuildOutputs
  class ContractError < StandardError; end

  class UniqueKeys < Hash
    def []=(key, value)
      raise ContractError, "Duplicate artifact manifest key: #{key}" if key?(key)

      super
    end
  end

  module_function

  def csv(value)
    return [] if value.to_s.empty?

    values = value.split(',', -1).map(&:strip)
    raise ContractError, 'Generated output/input lists must not contain empty entries.' if values.any?(&:empty?)
    raise ContractError, 'Generated output/input lists must not contain duplicate entries.' unless values.uniq == values

    values
  end

  def relative(value, label)
    unless value.is_a?(String) && !value.empty? && value !~ /[\s\x00-\x1f\x7f*?\[\]{}\\]/ &&
            !value.start_with?('/') && value.split('/').none? { |part| ['', '.', '..'].include?(part) }
      raise ContractError, "#{label} must be an explicit normalized repo-relative path: #{value.inspect}"
    end
    value
  end

  def contained(root, relative_path, label, forbid_links: false)
    path = File.join(root, relative_path)
    cursor = root
    relative_path.split('/').each do |part|
      cursor = File.join(cursor, part)
      if File.symlink?(cursor)
        raise ContractError, "#{label} must not use symbolic links: #{relative_path}" if forbid_links
        begin
          target = File.realpath(cursor)
        rescue SystemCallError
          raise ContractError, "#{label} contains a broken symbolic link: #{relative_path}"
        end
        unless target.start_with?(root + '/')
          raise ContractError, "#{label} escapes the repository: #{relative_path}"
        end
      end
      if File.exist?(cursor) && cursor != path && !File.directory?(cursor)
        raise ContractError, "#{label} parent is not a directory: #{relative_path}"
      end
    end
    path
  end

  # Configuration accepts ./ aliases and contained absolute source paths. Keep
  # lexical and resolved identities so an output declaration cannot erase an
  # input through a different spelling, symlink alias, or hard link.
  def protected_source_paths(root)
    %w[MAIN_PLUGIN_FILE README_FILE BUILD_SCRIPT DISTIGNORE_FILE
      WP_PLUGIN_BASE_SECURITY_SUPPRESSIONS_FILE CONFIG_PATH].flat_map do |key|
      value = ENV[key].to_s
      next [] if value.empty?

      absolute = File.expand_path(value, root)
      begin
        [absolute, File.realpath(absolute)]
      rescue Errno::ENOENT, Errno::ENOTDIR
        [absolute]
      end
    end.uniq
  end

  def protects_source?(root, value, sources, directory: false)
    output = File.expand_path(value, root)
    sources.any? do |source|
      next true if source == output || source.start_with?(output + '/') || File.identical?(source, output)
      next false unless directory

      # Identity comparisons also cover case aliases on case-insensitive file
      # systems, including an absent optional file beneath an existing parent.
      ancestor = File.dirname(source)
      matched = false
      loop do
        if File.identical?(ancestor, output)
          matched = true
          break
        end
        parent = File.dirname(ancestor)
        break if parent == ancestor

        ancestor = parent
      end
      matched
    end
  end

  def generated_path(value, root, sources)
    value = relative(value, 'Generated output')
    # Reserved roots are case-insensitive to keep the policy portable to default
    # macOS/Windows file systems, where DIST and dist identify the same tree.
    first = value.split('/').first.downcase
    if %w[.git .github .gitlab .wp-plugin-base dist node_modules vendor].include?(first) ||
        first.start_with?('.wp-plugin-base') ||
        %w[.gitlab-ci.yml .gitignore .gitattributes .editorconfig agents.md contributing.md security.md uninstall.php.example].include?(first) ||
        protects_source?(root, value, sources)
      raise ContractError, "Generated output uses a reserved/source path: #{value}"
    end
    value
  end

  def manifest_inventory(root, manifest, source_root, sources)
    path = contained(root, manifest, 'BUILD_OUTPUT_MANIFEST', forbid_links: true)
    raise ContractError, "Required build artifact manifest is missing: #{manifest}" unless File.file?(path)
    raise ContractError, 'Build artifact manifest exceeds 16 MiB.' if File.size(path) > 16 * 1024 * 1024

    data = JSON.parse(File.read(path), object_class: UniqueKeys)
    unless data.is_a?(Hash) && data.keys.sort == %w[artifacts schema_version] && data['schema_version'] == 1 &&
            data['artifacts'].is_a?(Array) && !data['artifacts'].empty?
      raise ContractError, 'Build artifact manifest requires schema_version=1 and a nonempty artifacts array.'
    end
    prefix = File.dirname(manifest) + '/'
    entries = {}
    data['artifacts'].each do |artifact|
      unless artifact.is_a?(Hash) && artifact.keys.sort == %w[path sha256] &&
              artifact['sha256'].is_a?(String) && artifact['sha256'].match?(/\A[0-9a-f]{64}\z/)
        raise ContractError, 'Every artifact must contain exactly path and a lowercase SHA-256 digest.'
      end
      name = generated_path(artifact['path'], source_root, sources)
      unless name.start_with?(prefix) && name != manifest && !entries.key?(name)
        raise ContractError, "Duplicate or out-of-directory artifact manifest entry: #{name}"
      end
      artifact_path = contained(root, name, 'Build artifact', forbid_links: true)
      unless File.file?(artifact_path) && Digest::SHA256.file(artifact_path).hexdigest == artifact['sha256']
        raise ContractError, "Missing or changed build artifact: #{name}"
      end
      entries[name] = true
    end
    actual = []
    Dir.glob(File.join(root, prefix, '**', '*'), File::FNM_DOTMATCH).each do |entry|
      next if %w[. ..].include?(File.basename(entry))

      name = entry.delete_prefix(root + '/')
      contained(root, name, 'Generated output tree', forbid_links: true)
      next if File.directory?(entry) || name == manifest
      raise ContractError, "Generated tree contains a nonregular artifact: #{name}" unless File.file?(entry)

      actual << name
    end
    unless actual.sort == entries.keys.sort
      raise ContractError, 'Build artifact manifest does not describe every generated file in its directory.'
    end
  rescue JSON::ParserError => e
    raise ContractError, "Invalid build artifact manifest JSON: #{e.message}"
  end

  def run(mode, stage_root)
    root = File.realpath(ENV.fetch('ROOT_DIR'))
    sources = protected_source_paths(root)
    # Main/readme are always source inputs. The custom script is required before
    # destructive preparation; sync retains its managed-admin first-generation
    # exception and the builder also checks the script before invoking this phase.
    required_sources = %w[MAIN_PLUGIN_FILE README_FILE]
    required_sources << 'BUILD_SCRIPT' if mode == 'prepare'
    required_sources.each do |key|
      value = ENV[key].to_s
      next if value.empty?
      raise ContractError, "Required source input not found: #{key}=#{value}" unless File.file?(File.expand_path(value, root))
    end
    outputs = csv(ENV['BUILD_OUTPUTS']).map { |value| generated_path(value, root, sources) }
    manifest = ENV['BUILD_OUTPUT_MANIFEST'].to_s
    unless manifest.empty?
      manifest = generated_path(manifest, root, sources)
      raise ContractError, 'BUILD_OUTPUT_MANIFEST must live in a dedicated generated directory.' if File.dirname(manifest) == '.'
      if protects_source?(root, File.dirname(manifest), sources, directory: true)
        raise ContractError, 'Generated manifest directory must not contain required source or configuration files.'
      end
    end
    declarations = outputs + (manifest.empty? ? [] : [manifest])
    if !declarations.empty? && ENV['BUILD_SCRIPT'].to_s.empty?
      raise ContractError, 'Declared generated outputs require BUILD_SCRIPT.'
    end
    declarations.each do |name|
      path = contained(root, name, 'Generated output', forbid_links: true)
      raise ContractError, "Generated output must declare a regular file, not a directory: #{name}" if File.exist?(path) && !File.file?(path)
    end
    csv(ENV['PACKAGE_INCLUDE']).each do |name|
      name = name.delete_prefix('./').sub(%r{/+\z}, '')
      name = relative(name, 'PACKAGE_INCLUDE') unless name == '.'
      path = contained(root, name, 'PACKAGE_INCLUDE')
      generated = declarations.any? { |output| output == name || output.start_with?(name + '/') } ||
                  (!manifest.empty? && name.start_with?(File.dirname(manifest) + '/'))
      unless File.exist?(path) || (%w[inputs prepare].include?(mode) && generated)
        raise ContractError, "PACKAGE_INCLUDE source path not found: #{name}"
      end
    end
    return if mode == 'inputs'
    if mode == 'prepare'
      unless manifest.empty?
        directory = File.dirname(manifest)
        tree = contained(root, directory, 'Generated output directory', forbid_links: true)
        Dir.glob(File.join(tree, '**', '*'), File::FNM_DOTMATCH).each do |entry|
          next if %w[. ..].include?(File.basename(entry))

          contained(root, entry.delete_prefix(root + '/'), 'Generated output tree', forbid_links: true)
        end
        FileUtils.rm_rf(tree)
      end
      outputs.each do |name|
        path = contained(root, name, 'Generated output', forbid_links: true)
        File.unlink(path) if File.file?(path)
      end
      return
    end

    target = File.realpath(stage_root || root)
    outputs.each do |name|
      path = contained(target, name, 'Required build artifact', forbid_links: true)
      raise ContractError, "Required build artifact is missing: #{name}" unless File.file?(path)
    end
    manifest_inventory(target, manifest, root, sources) unless manifest.empty?
  end
end

begin
  mode = ARGV.fetch(0)
  raise BuildOutputs::ContractError, 'Expected inputs, prepare or outputs mode.' unless %w[inputs prepare outputs].include?(mode)

  BuildOutputs.run(mode, ARGV[1])
rescue BuildOutputs::ContractError, SystemCallError, KeyError => e
  warn e.message
  exit 1
end
