import assert from 'node:assert/strict';

const severities = ['info', 'low', 'moderate', 'high', 'critical'];
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function classifyAudit(raw, status, verifiedRemediations, level = 'high') {
  assert(severities.includes(level), 'Invalid audit severity threshold');
  assert(Array.isArray(verifiedRemediations) && verifiedRemediations.length > 0, 'No verified remediations');
  assert(status === 0 || status === 1, 'npm audit execution failed');
  const report = JSON.parse(raw);
  assert(report.auditReportVersion === 2 && !report.error && record(report.vulnerabilities), 'Unsupported npm audit report');
  const counts = Object.fromEntries(severities.map(severity => [severity, 0]));
  const entries = report.vulnerabilities;
  for (const [name, item] of Object.entries(entries)) {
    assert(record(item) && item.name === name && severities.includes(item.severity), 'Invalid vulnerability record');
    assert(Array.isArray(item.via) && item.via.length > 0 && Array.isArray(item.effects), 'Missing dependency graph');
    assert(Array.isArray(item.nodes) && item.nodes.length > 0 && item.nodes.every(path => typeof path === 'string'), 'Missing installed dependency paths');
    assert(new Set(item.nodes).size === item.nodes.length && new Set(item.effects).size === item.effects.length, 'Duplicate advisory paths or edges');
    for (const via of item.via) {
      if (typeof via === 'string') {
        assert(Object.hasOwn(entries, via) && entries[via]?.effects.includes(name), 'Incomplete dependency advisory edge');
      } else {
        assert(record(via) && typeof via.url === 'string' && typeof via.name === 'string' && severities.includes(via.severity), 'Invalid advisory');
      }
    }
    for (const effect of item.effects) assert(typeof effect === 'string' && Object.hasOwn(entries, effect) && entries[effect]?.via.includes(name), 'Incomplete reverse advisory edge');
    const sourceSeverity = Math.max(...item.via.map(via => severities.indexOf(typeof via === 'string' ? entries[via].severity : via.severity)));
    assert.equal(severities.indexOf(item.severity), sourceSeverity, 'Unexplained aggregate advisory severity');
    counts[item.severity]++;
  }
  const total = Object.keys(entries).length;
  assert(record(report.metadata?.vulnerabilities), 'Missing advisory counts');
  assert.deepEqual(report.metadata.vulnerabilities, { ...counts, total }, 'Advisory count mismatch');
  assert.equal(status, total ? 1 : 0, 'Audit exit status contradicts findings');

  const cache = new Map();
  function residualSources(name, visiting = new Set()) {
    if (cache.has(name)) return cache.get(name);
    assert(!visiting.has(name), 'Cyclic advisory graph');
    const item = entries[name];
    const next = new Set([...visiting, name]);
    const sources = new Map();
    // Traverse every edge, including mixed remediated/unremediated paths.
    for (const via of item.via) {
      if (typeof via === 'string') {
        for (const [key, source] of residualSources(via, next)) sources.set(key, source);
        continue;
      }
      const remediation = verifiedRemediations.find(entry => via.url === `https://github.com/advisories/${entry.advisory}`);
      if (remediation) {
        assert(name === remediation.package && via.name === name && via.dependency === name && via.range === remediation.range && via.severity === remediation.severity, 'Reviewed advisory contract changed');
        assert(Array.isArray(remediation.nodes) && remediation.nodes.length > 0, 'No verified package instances');
        assert.deepEqual([...item.nodes].sort(), [...remediation.nodes].sort(), 'Incomplete or unverified package instances');
        continue;
      }
      const source = { url: via.url, package: name, severity: via.severity, range: via.range ?? null };
      sources.set(JSON.stringify(source), source);
    }
    cache.set(name, sources);
    return sources;
  }
  const locallyRemediated = [];
  const blocked = [];
  const residual = [];
  for (const [name, item] of Object.entries(entries)) {
    const sources = [...residualSources(name).values()];
    if (sources.length === 0) {
      locallyRemediated.push(name);
      continue;
    }
    const rank = Math.max(...sources.map(source => severities.indexOf(source.severity)));
    residual.push({ name, reportedSeverity: item.severity, severity: severities[rank], sources });
    if (rank >= severities.indexOf(level)) blocked.push(name);
  }
  return { locallyRemediated, residual, blocked };
}
