#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../lib/action_pins'

class ActionPinMigrationTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__).freeze

  def setup
    @directory = Dir.mktmpdir('foundation-action-pins-')
    @manifest = File.join(@directory, 'migrations.txt')
    @policy = WPPluginBaseActionPins.catalog
    @current = "actions/checkout@#{@policy.fetch('actions/checkout').fetch('current')}"
    @previous = "actions/checkout@#{@policy.fetch('actions/checkout').fetch('predecessors').first}"
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def write(path, source)
    absolute = File.join(@directory, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, source)
    absolute
  end

  def migrate(success: true)
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/migrate_action_pins.rb'), @directory, @manifest)
    assert_equal success, status.success?, output + error
  end

  def workflow(reference)
    "name: Custom\npermissions: {contents: read}\non: push\njobs:\n  custom:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: #{reference}\n"
  end

  def test_only_real_action_scalars_change_and_original_yaml_is_preserved
    source = <<~YAML
      # Keep #{@previous} in this comment.
      name: Custom
      permissions: {contents: read}
      on: push
      jobs:
        custom:
          runs-on: ubuntu-latest
          steps:
            - {name: 'Unicode 🔥', uses: '#{@previous}', with: {ref: main}} # retained
            - run: |
                uses: #{@previous}
            - uses: ./.github/actions/local
    YAML
    path = write('.github/workflows/custom.yml', source)
    migrate
    assert_equal source.sub("uses: '#{@previous}'", "uses: '#{@current}'"), File.read(path)
    assert_equal ".github/workflows/custom.yml\n", File.read(@manifest)
    WPPluginBaseActionPins.audit([path])
    migrated = File.read(path)
    migrate
    assert_equal migrated, File.read(path)
    assert_empty File.read(@manifest)
  end

  def test_composite_actions_and_reusable_job_references_are_inspected
    path = write('.github/actions/custom/action.yaml', "name: Custom\nruns:\n  using: composite\n  steps:\n    - uses: \"#{@previous}\" # Keep this\n")
    job = write('.github/workflows/reusable.yml', "permissions: {contents: read}\njobs:\n  call:\n    uses: #{@previous}\n")
    migrate
    assert_includes File.read(path), "uses: \"#{@current}\" # Keep this"
    assert_includes File.read(job), @current
    assert_equal ['.github/actions/custom/action.yaml', '.github/workflows/reusable.yml'], File.readlines(@manifest, chomp: true)
  end

  def test_unknown_pins_fail_without_partial_file_changes
    path = write('.github/workflows/a.yml', workflow(@previous))
    write('.github/workflows/z.yml', workflow('actions/checkout@' + 'a' * 40))
    migrate(success: false)
    assert_equal workflow(@previous), File.read(path)
    refute File.exist?(@manifest)
  end

  def test_duplicate_yaml_keys_cannot_hide_an_unapproved_reference
    path = write('.github/workflows/a.yml', workflow(@current).sub("      - uses: #{@current}", "      - uses: #{@current}\n        uses: unknown/action@" + 'a' * 40))
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) }
    migrate(success: false)
  end

  def test_literal_merge_keys_cannot_hide_an_unapproved_reference
    path = write('.github/workflows/a.yml', workflow(@current).sub("uses: #{@current}", "<<: {uses: unknown/action@" + 'a' * 40 + '}'))
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) }
    migrate(success: false)
  end

  def test_tags_are_never_promoted_to_reviewed_pins
    write('.github/workflows/a.yml', workflow('actions/checkout@v4'))
    migrate(success: false)
  end

  def test_auditor_rejects_predecessors_until_migrated
    path = write('.github/workflows/a.yml', workflow(@previous))
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) }
    migrate
    WPPluginBaseActionPins.audit([path])
  end

  def test_staging_manifest_contains_only_reviewed_workflow_and_action_paths
    write('.github/workflows/custom.yml', workflow(@previous))
    migrate
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/list_migrated_action_paths.rb'), @directory, @manifest)
    assert status.success?, error
    assert_equal ".github/workflows/custom.yml\n", output
    File.write(@manifest, "../outside.yml\n")
    _output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/list_migrated_action_paths.rb'), @directory, @manifest)
    refute status.success?, error
  end

  def test_pathspec_metacharacters_fail_before_writes_or_staging
    custom = write('.github/workflows/custom.yml', workflow(@previous))
    unrelated = write('.github/workflows/unrelated.yml', workflow(@current))
    _output, error, status = Open3.capture3('git', 'init', '-q', @directory)
    assert status.success?, error
    _output, error, status = Open3.capture3('git', '-C', @directory, 'add', '--', '.github/workflows/unrelated.yml')
    assert status.success?, error
    baseline, = Open3.capture3('git', '-C', @directory, 'ls-files', '--stage')
    File.write(unrelated, workflow(@current) + "# Unrelated work\n")
    ['*', '?', '[x]', ':', '\\'].each do |character|
      relative = ".github/workflows/#{character}.yml"
      unsafe = write(relative, workflow(@previous))
      migrate(success: false)
      assert_equal workflow(@previous), File.read(custom)
      assert_equal workflow(@previous), File.read(unsafe)
      refute File.exist?(@manifest)
      File.write(unsafe, workflow(@current))
      File.write(@manifest, ".github/workflows/unrelated.yml\n#{relative}\n")
      output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/list_migrated_action_paths.rb'), @directory, @manifest)
      refute status.success?, error
      assert_empty output, 'No paths may be published before every manifest path is validated'
      staged, = Open3.capture3('git', '-C', @directory, 'ls-files', '--stage')
      assert_equal baseline, staged, 'Unrelated dirty work must not enter the staging index'
      File.delete(unsafe)
      File.delete(@manifest)
    end
  end

  def test_migration_refuses_symbolic_links
    target = write('outside.yml', workflow(@previous))
    FileUtils.mkdir_p(File.join(@directory, '.github/workflows'))
    File.symlink(target, File.join(@directory, '.github/workflows/linked.yml'))
    migrate(success: false)
    assert_equal workflow(@previous), File.read(target)
  end

  def test_generated_dependabot_has_exact_catalog_ignores_and_child_npm_ownership
    write('package.json', '{}')
    write('composer.json', '{}')
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), File.join(ROOT, 'templates/child/.github/dependabot.yml'), @directory, 'true')
    assert status.success?, error
    updates = Psych.safe_load(output).fetch('updates')
    actions = updates.find { |update| update['package-ecosystem'] == 'github-actions' }
    expected = @policy.keys.map { |name| name.split('/').first(2).join('/') }.uniq.sort
    assert_equal expected, actions.fetch('ignore').map { |ignore| ignore.fetch('dependency-name') }
    assert_equal ['/', '/.wp-plugin-base-admin-ui'], updates.select { |update| update['package-ecosystem'] == 'npm' }.map { |update| update['directory'] }
    assert_equal 1, updates.count { |update| update['package-ecosystem'] == 'composer' }
    updates.reject { |update| update['package-ecosystem'] == 'github-actions' }.each { |update| refute update.key?('ignore') }
  end

  def test_dependabot_explicit_selection_does_not_add_other_ecosystems
    write('package.json', '{}')
    write('composer.json', '{}')
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), File.join(ROOT, 'templates/child/.github/dependabot.yml'), @directory, 'true', 'composer,npm')
    assert status.success?, error
    updates = Psych.safe_load(output).fetch('updates')
    assert_equal ['composer', 'npm'], updates.map { |update| update.fetch('package-ecosystem') }
    updates.each { |update| refute update.key?('ignore') }
  end

  def test_dependabot_rejects_invalid_selection
    ['auto,npm', 'github-actions,github-actions', 'unknown'].each do |selection|
      output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), File.join(ROOT, 'templates/child/.github/dependabot.yml'), @directory, 'true', selection)
      refute status.success?, error
      assert_empty output
    end
  end

end
