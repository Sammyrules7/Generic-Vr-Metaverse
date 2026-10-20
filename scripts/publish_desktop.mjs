#!/usr/bin/env node
import { openAsBlob } from 'node:fs';
import { appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export async function publish(env = process.env, request = fetch) {
  const { GITHUB_SERVER_URL: server, GITHUB_REPOSITORY: repo,
    GITHUB_SHA: commit, GITHUB_RUN_ID: run, EXPORT_DIR: directory } = env;
  const token = env.FORGEJO_TOKEN || env.GITHUB_TOKEN;
  if (!server || !repo || !/^[0-9a-f]{40}$/.test(commit) || !/^\d+$/.test(run) ||
      !directory || !token) throw new Error('Missing desktop release identity');
  const api = `${server}/api/v1/repos/${repo}/releases`;
  const headers = { Authorization: `token ${token}`, 'Content-Type': 'application/json' };
  const created = await request(api, {
    method: 'POST', redirect: 'error', headers,
    body: JSON.stringify({ tag_name: `desktop-${run}-${env.GITHUB_RUN_ATTEMPT || '1'}`,
      target_commitish: commit, name: `Generic-Vr-Platform desktop ${commit.slice(0, 8)}`,
      draft: true, prerelease: env.GITHUB_REF_NAME !== 'main',
      body: `Linux and Windows downloads. Extract the archive before running. Commit: ${commit}.` }),
    signal: AbortSignal.timeout(30000),
  });
  if (created.status !== 201) throw new Error(`Desktop draft release failed (HTTP ${created.status})`);
  const release = await created.json();
  const links = [];
  for (const platform of ['linux', 'windows']) {
    const name = `Generic-Vr-Platform-${platform}.tar.gz`;
    const form = new FormData();
    form.set('attachment', await openAsBlob(`${directory}/${name}`), name);
    const uploaded = await request(`${api}/${release.id}/assets?name=${name}`, {
      method: 'POST', redirect: 'error', headers: { Authorization: `token ${token}` },
      body: form, signal: AbortSignal.timeout(600000),
    });
    if (uploaded.status !== 201) throw new Error(`Desktop upload failed (HTTP ${uploaded.status}); release remains a draft`);
    const asset = await uploaded.json();
    if (new URL(asset.browser_download_url).origin !== 'https://forgejo.maio-tech.com') {
      throw new Error('Unexpected desktop download origin');
    }
    links.push(`- [${platform}](${asset.browser_download_url})`);
  }
  const published = await request(`${api}/${release.id}`, {
    method: 'PATCH', redirect: 'error', headers, body: JSON.stringify({ draft: false }),
    signal: AbortSignal.timeout(30000),
  });
  if (!published.ok) throw new Error(`Desktop publication failed (HTTP ${published.status})`);
  const summary = `\nDesktop downloads (${commit.slice(0, 8)}):\n${links.join('\n')}\n`;
  console.log(summary);
  if (env.GITHUB_STEP_SUMMARY) await appendFile(env.GITHUB_STEP_SUMMARY, summary);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  publish().catch(() => { console.error('Desktop publication failed; check release permissions and assets'); process.exitCode = 1; });
}
