# Project Setup

1. Add this repo into your project at `.wp-plugin-base/`.
2. Create `.wp-plugin-base.env` from `templates/child/.wp-plugin-base.env.example`.
3. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
4. Commit the generated files.
5. Configure GitHub Actions secrets and, if needed, the `WP_ORG_DEPLOY_ENABLED` GitHub Actions variable.

Your project should pin exact foundation tags and update through PRs rather than tracking a moving branch.

Using `git subtree` for the initial bootstrap is fine, but it is not required for the automated update path.
