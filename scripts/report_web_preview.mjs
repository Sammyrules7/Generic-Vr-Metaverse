#!/usr/bin/env node
import { pathToFileURL } from 'node:url';

// Commit statuses appear in the PR checks area. Never point a successful
// status at the moving PR alias: it must open the commit that passed.
export async function report(env = process.env, request = fetch) {
  const { BUILD_COMMIT: commit, BUILD_SLUG: slug, PREVIEW_STATUS: result,
    GITHUB_SERVER_URL: server, GITHUB_REPOSITORY: repo } = env;
  if (!/^[0-9a-f]{40}$/.test(commit) || !/^pr-[1-9][0-9]*$/.test(slug) ||
      !repo || !server) throw new Error('Missing PR preview identity');
  const token = env.FORGEJO_TOKEN || env.GITHUB_TOKEN;
  if (!token) throw new Error('Missing repository status credential');
  const statuses = {
    pending: ['pending', 'Building web preview'],
    success: ['success', 'Open this commit’s web preview'],
    failure: ['failure', 'Web preview failed; open the build log'],
    cancelled: ['error', 'Web preview cancelled; open the build log'],
  };
  if (!Object.hasOwn(statuses, result)) throw new Error('Unknown preview status');
  const [state, description] = statuses[result];
  const target = result === 'success'
    ? `https://app.vr.maio-tech.com/${slug}/${commit}/`
    : `https://forgejo.maio-tech.com/${repo}/actions/runs/${env.GITHUB_RUN_ID}`;
  const response = await request(`${server}/api/v1/repos/${repo}/statuses/${commit}`, {
    method: 'POST', redirect: 'error',
    headers: { Authorization: `token ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ context: 'preview/web', state, description, target_url: target }),
    signal: AbortSignal.timeout(30000),
  });
  if (response.status !== 201) throw new Error(`Preview status failed (HTTP ${response.status})`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  report().catch(() => { console.error('Could not report PR preview status'); process.exitCode = 1; });
}
