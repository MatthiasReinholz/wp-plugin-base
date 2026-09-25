# Package generations and local reliability

The native builder serializes cooperating builds in one checkout, including the
application-owned `BUILD_SCRIPT` and the snapshot of its outputs. It builds in a
new `dist/.generations/generation-*` directory, verifies the complete ZIP against
that staged tree, and only then publishes a generation descriptor. Missing,
extra, duplicate, unsafe, unreadable, corrupt or changed entries fail validation.
Archive entries must have the same file bytes and canonical modes as staging.
The ZIP invocation ignores implicit Info-ZIP environment options; the application
build otherwise retains its ordinary environment.

Each successful generation contains `package/<slug>/`, the configured ZIP, and
`generation.json`. The descriptor binds the ZIP SHA-256 to every staged path,
file digest and mode. Later builds never reuse or delete a completed generation.
Managed release jobs capture its paths once and use them for Plugin Check,
channel preflight, SBOM generation, signing, attestation, upload and deployment.
A checksum of the compatibility ZIP is not a lease on those mutable bytes.

For an application-owned local consumer:

```bash
result="$(mktemp)"
WP_PLUGIN_BASE_PACKAGE_RESULT_FILE="$result" \
  bash .wp-plugin-base/scripts/ci/build_zip.sh .wp-plugin-base.env
source .wp-plugin-base/scripts/lib/package_generation.sh
wp_plugin_base_capture_package "$result"
rm -f "$result"
# Use "$WP_PLUGIN_BASE_PACKAGE_DIR" and "$WP_PLUGIN_BASE_PACKAGE_ZIP" from here.
wp_plugin_base_check_captured_package
```

The result is data (`key=value` records), never shell code. The capture function
exports `WP_PLUGIN_BASE_PACKAGE_DIR`, `WP_PLUGIN_BASE_PACKAGE_ZIP`,
`WP_PLUGIN_BASE_PACKAGE_SBOM`, `WP_PLUGIN_BASE_PACKAGE_SIGNATURE`,
`WP_PLUGIN_BASE_PACKAGE_DESCRIPTOR` and `WP_PLUGIN_BASE_PACKAGE_SHA256`.
Release steps can write the same result records to their job output file. SBOM
and signature sidecars belong beside that generation's ZIP. The ZIP signature
and ZIP attestation do **not** independently authenticate the SBOM sidecar.

For backwards compatibility, successful builds also replace `dist/package/`
and `dist/<zip>` with copies, and write `dist/package-generation.json`. Those
paths represent the most recent completed build and must not be used by a
consumer that can overlap another build. Replacing their separate paths is not
an atomic pair. Cooperating managed consumers use retained generation paths.
Ordinary staging, compression or verification failures retain the previous
successful generation. Compatibility installation restores previous outputs if
an ordinary rename/copy operation fails. A failed command still returns failure;
callers must not treat an older package as a successful result of that attempt.

The per-checkout lock uses Python's Unix `fcntl` on supported macOS and Linux
filesystems. It covers cooperating foundation builders and recovery tools;
application code that independently writes shared build outputs must participate
in this lifecycle. It does not prevent a different process with the same user
permissions from modifying generation files or swapping filesystem paths.
Recovery rejects symlinks and unsupported output types at every known output and
ancestor before downloading/installing, and rechecks before installation. Signed
archives still receive path, type, collision, decompression and size checks.

Directories are 0755, ordinary files 0644 and files with any source executable bit
0755. Setuid, setgid and sticky bits are not propagated. ZIP timestamps are fixed
in UTC; root directory modes do not depend on the invoking umask. Recovery retains
this executable distinction and restores safe canonical modes, including implicit
directories in older archives. Byte reproducibility requires equal source bytes,
executable flags, generated outputs and compatible archive/compression toolchains;
this is not a promise across arbitrary tool versions or nondeterministic builds.

Interrupted processes, SIGKILL and power loss can leave partial attempts or
compatibility-install backups. This is not a crash-durable transaction protocol.
Do not automatically remove generations while consumers may still hold them.
Once **all** builds and consumers for a checkout have stopped, owners may remove
unneeded `dist/.generations/` directories and abandoned `.package-install-*`
directories. Keep any generation referenced by retained evidence or work still
being published. The entire `dist/` tree remains excluded from plugin packages.
