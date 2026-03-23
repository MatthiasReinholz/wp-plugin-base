# Troubleshooting

## Pull Request Creation Fails

Some foundation workflows create pull requests automatically, including:

- `prepare-release`
- `prepare-foundation-release`
- `update-foundation`

If those workflows fail when they try to open a pull request, check the GitHub Actions repository setting named `Allow GitHub Actions to create and approve pull requests`.

### Case 1: The Setting Is Available But Disabled

If the setting is visible in the repository settings, enable it:

1. Open your repository on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Find `Workflow permissions`.
4. Enable `Allow GitHub Actions to create and approve pull requests`.
5. Save the change and rerun the failed workflow.

Without that setting, workflows can still run, but workflows that use `create-pull-request` cannot open or update pull requests.

### Case 2: The Setting Is Greyed Out

If the setting is greyed out, the repository is usually inheriting an organization-level restriction.

In that case, an organization owner must allow it first:

1. Open the organization on GitHub.
2. Go to `Settings` -> `Actions` -> `General`.
3. Allow repositories in the organization to let GitHub Actions create and approve pull requests.
4. Return to the repository settings and enable the repository-level setting if GitHub still requires it there.

If you do not have organization admin access, ask an organization owner to make that change.

## Foundation Self-Update Cannot Open A PR

If `update-foundation` detects a newer version but fails during pull request creation, check both of these:

- `Allow GitHub Actions to create and approve pull requests` is enabled for the repository
- GitHub Actions in your repository can read releases from `FOUNDATION_REPOSITORY`

Both conditions are required for the automated update PR flow to work.
