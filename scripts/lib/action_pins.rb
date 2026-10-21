# Reviewed source policy shared by the workflow auditor and reviewed pin migrations.
require 'json'
require 'psych'

module WPPluginBaseActionPins
  CATALOG_PATH = File.join(__dir__, 'action-pins.json').freeze
  UNSAFE_PATH_CHARACTERS = ",:\r\n*?[]\\".chars.freeze

  # Manifests also feed comma-separated Git pathspecs in updater automation.
  def self.supported_path?(path)
    UNSAFE_PATH_CHARACTERS.none? { |character| path.include?(character) }
  end

  def self.catalog
    document = JSON.parse(File.read(CATALOG_PATH))
    raise 'Unsupported action pin catalog schema' unless document['schema_version'] == 1

    document.fetch('actions').each do |name, policy|
      raise "Invalid action identity: #{name}" unless name.match?(%r{\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*\z})
      pins = [policy.fetch('current')] + policy.fetch('predecessors')
      raise "Invalid or duplicate pins for #{name}" unless pins.uniq == pins && pins.all? { |pin| pin.match?(/\A[0-9a-f]{40}\z/) }
    end
  end

  def self.mapping_value(node, key)
    return nil unless node.is_a?(Psych::Nodes::Mapping)

    node.children.each_slice(2) do |name, value|
      return value if name.is_a?(Psych::Nodes::Scalar) && name.value == key
    end
    nil
  end

  def self.validate_ast(node)
    return unless node
    if node.is_a?(Psych::Nodes::Mapping)
      keys = node.children.each_slice(2).map(&:first)
      unless keys.all? { |key| key.is_a?(Psych::Nodes::Scalar) && key.value != '<<' } && keys.map(&:value).uniq.length == keys.length
        raise 'Duplicate, merged, or non-scalar YAML keys require manual review'
      end
    end
    (node.children || []).each { |child| validate_ast(child) }
  end

  def self.references(file)
    # Psych reports character columns for UTF-8 input; read UTF-8 explicitly so
    # offsets still match under a C/POSIX locale (minimal runner images).
    source = File.read(file, mode: 'r:UTF-8')
    Psych.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false, filename: file)
    stream = Psych.parse_stream(source, filename: file)
    raise "#{file}: exactly one YAML document is required" unless stream.children.length == 1
    root = stream.children.first.root
    validate_ast(root)
    references = []
    collect_steps = lambda do |steps|
      next unless steps.is_a?(Psych::Nodes::Sequence)

      steps.children.each do |step|
        value = mapping_value(step, 'uses')
        references << value if value
      end
    end
    jobs = mapping_value(root, 'jobs')
    if jobs.is_a?(Psych::Nodes::Mapping)
      jobs.children.each_slice(2) do |_name, job|
        value = mapping_value(job, 'uses')
        references << value if value
        collect_steps.call(mapping_value(job, 'steps'))
      end
    end
    runs = mapping_value(root, 'runs')
    collect_steps.call(mapping_value(runs, 'steps')) if mapping_value(runs, 'using')&.value == 'composite'
    references.each do |value|
      raise "#{file}: action reference must be a scalar" unless value.is_a?(Psych::Nodes::Scalar)
    end
    [source, references]
  end

  PINNED_REFERENCE = %r{\A([A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*)@([0-9a-f]{40})\z}

  # Projects may move pins past the catalog, for example through their own
  # Dependabot updates. Migration only replaces reviewed predecessors, so it
  # never downgrades a project pin; project audits accept every full-SHA pin.
  def self.replacement(reference, policy, migrate: false, project: false)
    return reference if reference.start_with?('./')
    match = PINNED_REFERENCE.match(reference)
    raise "action reference must be pinned to a full-length commit SHA: #{reference}" unless match

    name, pin = match.captures
    entry = policy[name]
    return reference if entry && pin == entry['current']
    return "#{name}@#{entry['current']}" if migrate && entry && entry['predecessors'].include?(pin)
    return reference if migrate || project

    raise "action is not in the approved allowlist: #{reference}"
  end

  # Edit only the parsed reference scalars chosen by the block; every other
  # source byte is preserved.
  def self.rewrite_references(file, source, references)
    offsets = [0]
    source.lines.each { |line| offsets << offsets.last + line.length }
    replacements = []
    references.each do |node|
      replacement = yield(node)
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
    result = source.dup
    replacements.sort_by(&:first).reverse_each { |start, finish, replacement| result[start...finish] = replacement }
    result
  end

  def self.audit(files, project: false)
    policy = catalog
    unreviewed = []
    files.each do |file|
      _source, references = references(file)
      references.each do |node|
        begin
          replacement(node.value, policy, project: project)
        rescue StandardError => error
          raise "#{file}:#{node.start_line + 1}: #{error.message}"
        end
        name, pin = node.value.split('@', 2)
        unreviewed << node.value if project && policy.dig(name, 'current') != pin && !node.value.start_with?('./')
      end
    end
    unreviewed.uniq.each { |reference| puts "Project-owned action pin (not the current wp-plugin-base reviewed pin): #{reference}" }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    WPPluginBaseActionPins.audit(ARGV, project: ENV['WP_PLUGIN_BASE_ACTION_PIN_POLICY'] == 'project')
  rescue StandardError => error
    warn(error.message)
    exit 1
  end
end
