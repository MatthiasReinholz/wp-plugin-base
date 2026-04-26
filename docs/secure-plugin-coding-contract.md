# Secure Plugin Coding Contract

Use this contract when coding manually or with coding agents such as Codex or Claude Code.

## Required Security Rules

1. Authorization first:
   - All privileged actions must enforce capability checks (`current_user_can(...)`) before side effects.
   - REST endpoints must use explicit `permission_callback` logic that enforces capability and context.

2. CSRF protection:
   - Any state-changing request from wp-admin, AJAX, or forms must verify a nonce (`check_admin_referer`, `check_ajax_referer`, or equivalent).

3. Input handling:
   - Treat all external input as untrusted.
   - Validate expected type/shape and sanitize with WordPress APIs before use.

4. Output handling:
   - Escape on output (`esc_html`, `esc_attr`, `esc_url`, `wp_kses_post`, etc.) for every rendered value.

5. Database safety:
   - Use `$wpdb->prepare(...)` for dynamic SQL fragments.
   - Avoid direct unprepared SQL.

6. Public endpoint hardening:
   - `wp_ajax_nopriv_*`, `admin_post_nopriv_*`, and REST routes with `permission_callback => __return_true` are blocked by default and require explicit security review.
   - intentionally public operations declared through the managed REST operations pack require a `rest_public_operation` suppression entry with written justification.
   - legacy direct `register_rest_route()` usage in projects that enable the managed REST operations pack is blocked by default and requires a justified `rest_route_bypass` suppression during migration.

## Suppression Contract For Intentional Public Endpoints

If a public endpoint is intentional, add a suppression entry to `.wp-plugin-base-security-suppressions.json` with a mandatory justification.

Example:

```json
{
  "suppressions": [
    {
      "kind": "wp_ajax_nopriv",
      "identifier": "my_public_action",
      "path": "includes/class-public-endpoints.php",
      "justification": "Anonymous endpoint required for checkout preflight; verifies nonce, rate limits requests, and returns non-sensitive data only."
    }
  ]
}
```

Allowed `kind` values:

- `wp_ajax_nopriv`
- `admin_post_nopriv`
- `rest_permission_callback_true`
- `rest_permission_callback_missing`
- `rest_public_operation`
- `rest_route_bypass`

## Agent Prompting Hints

When asking an agent to implement code, include explicit constraints:

- "Enforce capability and nonce checks before state changes."
- "Sanitize all input and escape all output with WordPress APIs."
- "Do not use `permission_callback => __return_true` unless paired with a justified suppression entry."
- "Use `$wpdb->prepare` for all dynamic SQL."

This keeps generated code aligned with the foundation security gates and avoids noisy rework in CI.
