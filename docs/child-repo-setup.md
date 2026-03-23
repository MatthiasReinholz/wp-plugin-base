# Child Repo Setup

1. Add this repo into the child repo at `.wp-plugin-base/`.
2. Create `.wp-plugin-base.env` from `templates/child/.wp-plugin-base.env.example`.
3. Run `bash .wp-plugin-base/scripts/update/sync_child_repo.sh`.
4. Commit the generated files.
5. Configure GitHub secrets and the optional `WP_ORG_DEPLOY_ENABLED` variable.

Child repos should pin exact foundation tags and update through PRs rather than tracking a moving branch.
