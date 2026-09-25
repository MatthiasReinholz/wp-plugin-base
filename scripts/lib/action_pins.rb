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
    source = File.read(file)
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

  def self.replacement(reference, policy, migrate: false)
    return reference if reference.start_with?('./')
    unless reference.match?(%r{\A[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*@[0-9a-f]{40}\z})
      raise "action reference must be pinned to a full-length commit SHA: #{reference}"
    end
    name, pin = reference.split('@', 2)
    entry = policy[name]
    return reference if entry && pin == entry['current']
    return "#{name}@#{entry['current']}" if migrate && entry && entry['predecessors'].include?(pin)

    raise "action is not in the approved allowlist: #{reference}"
  end

  def self.audit(files)
    policy = catalog
    files.each do |file|
      _source, references = references(file)
      references.each do |node|
        begin
          replacement(node.value, policy)
        rescue StandardError => error
          raise "#{file}:#{node.start_line + 1}: #{error.message}"
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    WPPluginBaseActionPins.audit(ARGV)
  rescue StandardError => error
    warn(error.message)
    exit 1
  end
end
