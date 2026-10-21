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

  def migrate(success: true, env: {})
    output, error, status = Open3.capture3(env, 'ruby', File.join(ROOT, 'scripts/update/migrate_action_pins.rb'), @directory, @manifest)
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
    assert_equal source.sub("uses: '#{@previous}'", "uses: '#{@current}'"), File.read(path, mode: 'r:UTF-8')
    assert_equal ".github/workflows/custom.yml\n", File.read(@manifest)
    WPPluginBaseActionPins.audit([path])
    migrated = File.read(path, mode: 'r:UTF-8')
    migrate
    assert_equal migrated, File.read(path, mode: 'r:UTF-8')
    assert_empty File.read(@manifest)
  end

  def test_non_ascii_sources_migrate_under_a_c_locale
    source = "name: Custom\npermissions: {contents: read}\non: push\njobs:\n  custom:\n    runs-on: ubuntu-latest\n" \
      "    steps:\n      - {name: 'Unicode 🔥 ü', uses: '#{@previous}'}\n"
    path = write('.github/workflows/custom.yml', source)
    migrate(env: { 'LANG' => 'C', 'LC_ALL' => 'C' })
    assert_equal source.sub(@previous, @current), File.read(path, mode: 'r:UTF-8')
  end

  def test_composite_actions_and_reusable_job_references_are_inspected
    path = write('.github/actions/custom/action.yaml', "name: Custom\nruns:\n  using: composite\n  steps:\n    - uses: \"#{@previous}\" # Keep this\n")
    job = write('.github/workflows/reusable.yml', "permissions: {contents: read}\njobs:\n  call:\n    uses: #{@previous}\n")
    migrate
    assert_includes File.read(path), "uses: \"#{@current}\" # Keep this"
    assert_includes File.read(job), @current
    assert_equal ['.github/actions/custom/action.yaml', '.github/workflows/reusable.yml'], File.readlines(@manifest, chomp: true)
  end

  def test_project_pins_are_kept_while_reviewed_predecessors_migrate
    path = write('.github/workflows/a.yml', workflow(@previous))
    project = write('.github/workflows/z.yml', workflow('actions/checkout@' + 'a' * 40))
    added = write('.github/workflows/y.yml', workflow('example/action@' + 'b' * 40))
    migrate
    assert_equal workflow(@current), File.read(path)
    assert_equal workflow('actions/checkout@' + 'a' * 40), File.read(project)
    assert_equal workflow('example/action@' + 'b' * 40), File.read(added)
    assert_equal ".github/workflows/a.yml\n", File.read(@manifest)
  end

  def test_unpinned_references_fail_without_partial_file_changes
    path = write('.github/workflows/a.yml', workflow(@previous))
    write('.github/workflows/z.yml', workflow('actions/checkout@main'))
    migrate(success: false)
    assert_equal workflow(@previous), File.read(path)
    refute File.exist?(@manifest)
  end

  def test_duplicate_yaml_keys_cannot_hide_an_unapproved_reference
    path = write('.github/workflows/a.yml', workflow(@current).sub("      - uses: #{@current}", "      - uses: #{@current}\n        uses: unknown/action@" + 'a' * 40))
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) }
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path], project: true) }
    migrate(success: false)
  end

  def test_literal_merge_keys_cannot_hide_an_unapproved_reference
    path = write('.github/workflows/a.yml', workflow(@current).sub("uses: #{@current}", "<<: {uses: unknown/action@" + 'a' * 40 + '}'))
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) }
    assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path], project: true) }
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

  # Foundation audits stay strict; projects own any full-SHA pin they choose.
  def test_project_audit_accepts_project_pins_but_requires_full_shas
    newer = write('.github/workflows/newer.yml', workflow('actions/checkout@' + 'a' * 40))
    older = write('.github/workflows/older.yml', workflow(@previous))
    added = write('.github/workflows/added.yml', workflow('example/action@' + 'b' * 40))
    [newer, older, added].each { |path| assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path]) } }
    output, = capture_io { WPPluginBaseActionPins.audit([newer, older, added], project: true) }
    assert_includes output, 'actions/checkout@' + 'a' * 40
    assert_includes output, 'example/action@' + 'b' * 40
    ['actions/checkout@v4', 'actions/checkout@' + 'a' * 39].each do |reference|
      path = write('.github/workflows/unpinned.yml', workflow(reference))
      assert_raises(RuntimeError) { WPPluginBaseActionPins.audit([path], project: true) }
    end
    _output, error, status = Open3.capture3({ 'WP_PLUGIN_BASE_ACTION_PIN_POLICY' => 'project' }, 'ruby', File.join(ROOT, 'scripts/lib/action_pins.rb'), newer)
    assert status.success?, error
    _output, _error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/lib/action_pins.rb'), newer)
    refute status.success?
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

  def test_generated_dependabot_leaves_actions_to_projects_and_groups_child_npm
    write('package.json', '{}')
    write('composer.json', '{}')
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), File.join(ROOT, 'templates/child/.github/dependabot.yml'), @directory, 'true')
    assert status.success?, error
    updates = Psych.safe_load(output).fetch('updates')
    actions = updates.find { |update| update['package-ecosystem'] == 'github-actions' }
    # Projects own action pins, so the current generation ignores no actions and
    # Dependabot security updates reach every workflow.
    refute actions.key?('ignore')
    assert_equal ['/', '/.wp-plugin-base-admin-ui'], updates.select { |update| update['package-ecosystem'] == 'npm' }.map { |update| update['directory'] }
    assert_equal 1, updates.count { |update| update['package-ecosystem'] == 'composer' }
    updates.each do |update|
      if update['package-ecosystem'] == 'npm'
        assert_equal({ 'wordpress-packages' => { 'patterns' => ['@wordpress/*'] } }, update['groups'])
      else
        refute update.key?('groups')
      end
    end
  end

  def test_dependabot_template_without_npm_additions_renders_previous_generation
    write('package.json', '{}')
    template = File.read(File.join(ROOT, 'templates/child/.github/dependabot.yml'))
    previous = write('previous.yml', template.sub(/^  - package-ecosystem: npm\n.*/m, ''))
    output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), previous, @directory, 'false')
    assert status.success?, error
    refute_includes output, 'groups:'
    updates = Psych.safe_load(output).fetch('updates')
    assert_equal 2, updates.length
    ignores = updates.first.fetch('ignore').map { |ignore| ignore.fetch('dependency-name') }
    assert_equal @policy.keys.map { |name| name.split('/').first(2).join('/') }.uniq.sort, ignores
  end

  def test_dependabot_rejects_npm_additions_beyond_groups
    template = File.read(File.join(ROOT, 'templates/child/.github/dependabot.yml'))
    [
      template.sub("  - package-ecosystem: npm\n", "  - package-ecosystem: npm\n    directory: /\n"),
      template.sub("  - package-ecosystem: npm\n", "  - package-ecosystem: composer\n"),
      template.sub('          - "@wordpress/*"', '          - 1'),
      template.sub('          - "@wordpress/*"', '          - ""'),
      template.chomp,
      template + "registries: {}\n",
      template.sub("    commit-message:\n", "    groups:\n      all:\n        patterns:\n          - \"*\"\n    commit-message:\n")
    ].each do |source|
      refute_equal template, source
      output, error, status = Open3.capture3('ruby', File.join(ROOT, 'scripts/update/render_child_dependabot.rb'), write('invalid.yml', source), @directory, 'true', 'github-actions,npm,admin-ui-npm')
      refute status.success?, error
      assert_empty output
    end
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
