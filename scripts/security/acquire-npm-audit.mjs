#!/usr/bin/env node
// Use npm's official audit engine/reporter without its independently bundled CLI graph.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { qualifiedAuditProducer, isMainModule } from './npm-remediation.mjs';

if (isMainModule(import.meta.url)) {
  try {
    const [projectFlag, project, toolsFlag, tools, ...extra] = process.argv.slice(2);
    assert(projectFlag === '--project-root' && project && toolsFlag === '--audit-tools' && tools && extra.length === 0, 'Expected --project-root PATH --audit-tools PATH');
    const { root } = qualifiedAuditProducer(tools);
    const require = createRequire(join(root, 'package.json'));
    const Arborist = require(join(root, 'node_modules/@npmcli/arborist'));
    const report = require(join(root, 'node_modules/npm-audit-report'));
    const options = {
      path: resolve(project), cache: join(root, '.audit-cache'), audit: true, reporter: 'json', auditLevel: 'info',
      registry: 'https://registry.npmjs.org', omit: [], include: ['dev', 'optional', 'peer'],
      workspaces: [], workspacesEnabled: false, global: false, ignoreScripts: true,
      packageLock: true, packageLockOnly: false,
    };
    const arborist = new Arborist(options);
    await arborist.audit({ fix: false });
    if (arborist.auditReport.error) throw arborist.auditReport.error;
    const result = report(arborist.auditReport, options);
    process.stdout.write(result.report + '\n');
    process.exitCode = result.exitCode;
  } catch (error) {
    console.error(`npm audit acquisition failed: ${error.message}`);
    process.exitCode = 2;
  }
}
