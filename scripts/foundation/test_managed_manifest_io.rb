#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'psych'
require_relative '../lib/managed_manifest_io'

class ManagedManifestIOTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__).freeze
  TEMPLATE = File.join(ROOT, 'templates/child').freeze

  class ScriptedWriter
    attr_reader :content

    def initialize(actions)
      @actions = actions
      @content = ''.b
    end

    def syswrite(content)
      action = @actions.shift
      raise action if action.is_a?(Exception)

      count = action || content.bytesize
      @content << content.byteslice(0, count)
      count
    end
  end

  def setup
    @temporary = Dir.mktmpdir('foundation-manifest-')
    @child = File.join(@temporary, 'child')
    FileUtils.cp_r(File.join(ROOT, 'tests/fixtures/standard-plugin'), @child)
    File.symlink(ROOT, File.join(@child, '.wp-plugin-base'))
    @environment = {'WP_PLUGIN_BASE_ROOT' => @child}
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def shell(source, environment = {})
    Open3.capture3(@environment.merge(environment), '/bin/bash', '-c', source, 'fixture', ROOT, TEMPLATE)
  end

  def library_source
    <<~BASH
      set -euo pipefail
      source "$1/scripts/lib/load_config.sh"
      wp_plugin_base_load_config
      source "$1/scripts/lib/managed_files.sh"
    BASH
  end

  def inject_find_failure
    bin = File.join(@temporary, 'bin')
    FileUtils.mkdir_p(bin)
    path = File.join(bin, 'find')
    File.write(path, <<~BASH)
      #!/usr/bin/env bash
      case "$1" in
        */qit-pack)
          printf '%s/.github/workflows/woocommerce-qit.yml\n' "$1"
          exit 37
          ;;
      esac
      exec /usr/bin/find "$@"
    BASH
    File.chmod(0o755, path)
    {'PATH' => "#{bin}:#{ENV.fetch('PATH')}"}
  end

  def enable_qit
    File.open(File.join(@child, '.wp-plugin-base.env'), 'a') do |file|
      file.puts "\nWOOCOMMERCE_QIT_ENABLED=true\nWOOCOMMERCE_COM_PRODUCT_ID=123"
    end
  end

  def test_interrupted_and_short_writes_preserve_exact_bytes
    writer = ScriptedWriter.new([Errno::EINTR.new, 3, Errno::EINTR.new, 2])
    content = "source\tpath\nsecond\tother\n".b
    WPPluginBaseManagedManifestIO.write_all(writer, content)
    assert_equal content, writer.content
  end

  def test_permanent_or_zero_progress_write_errors_fail
    [Errno::EIO.new, Errno::EPIPE.new, 0].each do |failure|
      writer = ScriptedWriter.new([3, failure])
      assert_raises(SystemCallError, IOError) do
        WPPluginBaseManagedManifestIO.write_all(writer, "complete manifest\n")
      end
      assert_equal 'com', writer.content
    end
  end

  def test_read_failure_publishes_nothing
    writer = ScriptedWriter.new([])
    assert_raises(Errno::ENOENT) do
      WPPluginBaseManagedManifestIO.publish(File.join(@temporary, 'missing'), writer)
    end
    assert_empty writer.content
  end

  def test_deduplication_preserves_first_occurrence_order
    path = File.join(@temporary, 'manifest')
    File.binwrite(path, "second\nfirst\nsecond\nthird\n")
    writer = ScriptedWriter.new([])
    WPPluginBaseManagedManifestIO.publish(path, writer, unique: true)
    assert_equal "second\nfirst\nthird\n", writer.content
  end

  def test_missing_optional_packs_remain_successful_empty_manifests
    %w[optional_managed seed].each do |kind|
      output, error, status = shell(library_source + "wp_plugin_base_print_#{kind}_template_pairs absent \"$2\"\n")
      assert status.success?, error
      assert_empty output
    end
  end

  def test_enumeration_failure_never_publishes_a_partial_manifest
    enable_qit
    %w[managed_template_pairs managed_paths all_managed_paths].each do |kind|
      output, error, status = shell(library_source + "wp_plugin_base_print_#{kind} \"$2\"\n", inject_find_failure)
      refute status.success?, error
      assert_empty output
    end
  end

  def test_regular_file_write_failure_never_publishes_a_partial_manifest
    enable_qit
    injection = <<~BASH
      printf() {
        if [ "${3:-}" = '.github/workflows/woocommerce-qit.yml' ]; then
          builtin printf '%s' 'partial row'
          return 37
        fi
        builtin printf "$@"
      }
      wp_plugin_base_print_managed_paths "$2"
    BASH
    output, error, status = shell(library_source + injection)
    refute status.success?, error
    assert_empty output
  end

  def test_list_command_checks_every_stage_producer
    %w[validate stage].each do |mode|
      enable_qit
      output, error, status = shell('bash "$1/scripts/ci/list_managed_files.sh" --mode ' + mode, inject_find_failure)
      refute status.success?, error
      assert_empty output
    end
  end

  def test_sync_checks_late_cleanup_manifest_before_any_mutation
    config = File.join(@child, '.wp-plugin-base.env')
    previous_config = File.binread(config)
    sentinel = File.join(@child, '.editorconfig')
    File.write(sentinel, "consumer sentinel\n")
    vendor = File.join(@child, 'lib/wp-plugin-base/plugin-update-checker')
    FileUtils.mkdir_p(vendor)
    File.write(File.join(vendor, 'sentinel'), 'preserve vendor')
    # QIT is disabled here, so only the final cleanup-union producer fails.
    _output, error, status = shell('bash "$1/scripts/update/sync_child_repo.sh"', inject_find_failure)
    refute status.success?, error
    assert_equal previous_config, File.binread(config)
    assert_equal "consumer sentinel\n", File.binread(sentinel)
    assert_equal 'preserve vendor', File.binread(File.join(vendor, 'sentinel'))
    refute File.exist?(File.join(@child, '.github'))
  end

  def test_project_validation_checks_manifest_status
    enable_qit
    _output, error, status = shell('bash "$1/scripts/ci/validate_project.sh"', inject_find_failure)
    refute status.success?, error
    assert_includes error, 'Cannot generate the managed file manifest.'
  end

  def test_native_bash_repeated_full_manifest_has_stable_complete_bytes
    source = library_source + <<~BASH
      expected="$(wp_plugin_base_print_all_managed_paths "$2")"
      for iteration in {1..20}; do
        actual="$(wp_plugin_base_print_all_managed_paths "$2")" || exit 1
        [ "$actual" = "$expected" ] || exit 1
        grep -Fxq '.github/workflows/woocommerce-qit.yml' <<< "$actual" || exit 1
      done
    BASH
    _output, error, status = shell(source)
    assert status.success?, error
  end

  def test_update_staging_rejects_failed_manifest_before_publication
    snippets = [
      File.read(File.join(ROOT, 'scripts/update/run_foundation_update.sh'))[/managed_paths="\$\(.*?^\)"/m]
    ]
    %w[.github/workflows/update-foundation.yml templates/child/.github/workflows/update-foundation.yml].each do |path|
      document = Psych.safe_load(File.read(File.join(ROOT, path)), aliases: false)
      step = document.fetch('jobs').values.flat_map { |job| job.fetch('steps', []) }
        .find { |item| item['name'] == 'Resolve managed staging paths' }
      snippets << step.fetch('run').sub(/\n\s*echo "value=.*\z/m, '')
    end
    snippets.each do |snippet|
      refute_nil snippet
      snippet = snippet.gsub('${{ inputs.config_path }}', '.wp-plugin-base.env')
      source = <<~BASH
        set -euo pipefail
        ROOT_DIR="$1"
        CONFIG_OVERRIDE=.wp-plugin-base.env
        migration_paths=fixture
        RUNNER_TEMP="$1"
        bash() { return 37; }
        ruby() { builtin printf '%s\\n' '.github/workflows/retained.yml'; }
        #{snippet}
        builtin printf '%s\\n' 'UNSAFE_SUCCESS'
      BASH
      output, error, status = shell(source)
      refute status.success?, error
      refute_includes output, 'UNSAFE_SUCCESS'
    end
  end
end
