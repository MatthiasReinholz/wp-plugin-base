<?php
// Intentionally unsafe scan inputs. This fixture is never executed.

// ruleid: wp-rest-permission-callback-true-string
register_rest_route('fixture/v1', '/string', [
  'permission_callback' => '__return_true',
]);

// Semgrep normalizes static and non-static closures; both rules detect each form.
// ruleid: wp-rest-permission-callback-true-callback, wp-rest-permission-callback-true-static-callback
register_rest_route('fixture/v1', '/closure', [
  'permission_callback' => function () { return true; },
]);

// ruleid: wp-rest-permission-callback-true-callback, wp-rest-permission-callback-true-static-callback
register_rest_route('fixture/v1', '/static', [
  'permission_callback' => static function () { return true; },
]);

register_rest_route('fixture/v1', '/arrow', [
  // ruleid: wp-rest-permission-callback-true-arrow
  'permission_callback' => fn () => true,
]);

// ok: wp-rest-permission-callback-true-string
register_rest_route('fixture/v1', '/named-check', [
  'permission_callback' => 'fixture_check_permission',
]);

// ok: wp-rest-permission-callback-true-callback, wp-rest-permission-callback-true-static-callback
register_rest_route('fixture/v1', '/checked-closure', [
  'permission_callback' => function () { return current_user_can('manage_options'); },
]);

// ok: wp-rest-permission-callback-true-callback, wp-rest-permission-callback-true-static-callback
register_rest_route('fixture/v1', '/checked-static', [
  'permission_callback' => static function () { return current_user_can('manage_options'); },
]);

register_rest_route('fixture/v1', '/checked-arrow', [
  // ok: wp-rest-permission-callback-true-arrow
  'permission_callback' => fn () => current_user_can('manage_options'),
]);
