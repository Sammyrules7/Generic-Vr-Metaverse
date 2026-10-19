import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { publish, versionWebhook } from '../publish_quest.mjs';

const webhook = 'https://api.sidequestvr.com/apps/release-webhook/private-test-token';

test('convert release or existing version webhook without exposing its token', () => {
  assert.equal(versionWebhook(webhook, '123').pathname, '/apps/version-webhook/123/private-test-token');
  assert.equal(versionWebhook(webhook.replace('release-webhook', 'version-webhook/12'), '123').pathname, '/apps/version-webhook/123/private-test-token');
  for (const bad of ['http://api.sidequestvr.com/apps/release-webhook/token',
    'https://example.org/release-webhook/token', 'https://api.sidequestvr.com/unknown']) {
    assert.throws(() => versionWebhook(bad, '123'));
  }
});

async function fixture(overrides, replies, verify) {
  const root = await mkdtemp(join(tmpdir(), 'quest-publish-'));
  try {
    const apk = join(root, 'client.apk');
    const summary = join(root, 'summary.md');
    await writeFile(apk, 'signed-apk-fixture');
    const env = { APK_PATH: apk, VERSION_CODE: '123', VERSION_NAME: '0.1.123',
      GITHUB_SERVER_URL: 'https://forgejo.example', GITHUB_REPOSITORY: 'owner/project',
      GITHUB_TOKEN: 'forgejo-test-token', GITHUB_SHA: 'a'.repeat(40),
      GITHUB_REF_NAME: 'test-branch', SIDEQUEST_WEBHOOK_URL: webhook,
      NOTIFY_SIDEQUEST: 'true', GITHUB_STEP_SUMMARY: summary, ...overrides };
    const calls = [];
    const request = async (url, options) => {
      calls.push({ url: String(url), ...options });
      if (options.body?.[Symbol.asyncIterator]) {
        for await (const chunk of options.body) assert.ok(chunk.length);
      }
      const reply = replies.shift();
      assert.ok(reply, 'Unexpected request');
      return new Response(reply.body ?? null, { status: reply.status,
        headers: reply.headers || {} });
    };
    await verify(() => publish(env, request), calls, () => readFile(summary, 'utf8'));
  } finally { await rm(root, { recursive: true, force: true }); }
}
const apkUrl = 'https://forgejo.example/owner/project/releases/download/quest-v0.1.123/Generic-Vr-Platform.apk';
const created = () => ({ status: 201, body: JSON.stringify({ id: 42 }) });
const uploaded = () => ({ status: 201, body: JSON.stringify({ browser_download_url: apkUrl }) });
const published = () => ({ status: 200 });
const visible = () => ({ status: 206, headers: { 'content-range': 'bytes 0-0/18' } });

test('publish draft with signed APK, verify public download, then notify', async () => {
  await fixture({}, [created(), uploaded(), published(), visible(), { status: 200 }], async (run, calls, summary) => {
    await run();
    assert.deepEqual(calls.map(x => x.method), ['POST', 'POST', 'PATCH', 'GET', 'POST']);
    assert.equal(calls[0].headers.Authorization, 'token forgejo-test-token');
    assert.equal(calls[1].headers.Authorization, 'token forgejo-test-token');
    assert.equal(calls[1].body.get('attachment').name, 'Generic-Vr-Platform.apk');
    const release = JSON.parse(calls[0].body);
    assert.equal(release.target_commitish, 'a'.repeat(40));
    assert.equal(release.draft, true);
    assert.equal(release.prerelease, true);
    assert.equal(calls[3].headers.Authorization, undefined);
    assert.equal(calls[4].headers.Authorization, undefined);
    assert.deepEqual(JSON.parse(calls[4].body), { url: apkUrl });
    assert.ok(calls[4].url.includes('/version-webhook/123/'));
    assert.ok((await summary()).includes(apkUrl));
    assert.ok(!(await summary()).includes('private-test-token'));
  });
});

test('failed upload or private APK must never reach SideQuest', async () => {
  for (const replies of [[{ status: 403 }], [created(), { status: 500 }],
    [created(), uploaded(), published(), { status: 401 }]]) {
    await fixture({}, replies, async (run, calls) => {
      await assert.rejects(run);
      assert.ok(calls.every(x => !x.url.includes('sidequestvr.com')));
    });
  }
});

test('retired webhook fails clearly while preserving the APK link', async () => {
  for (const reply of [{ status: 410 }, { status: 200, body: 'No! repo' }]) {
    await fixture({}, [created(), uploaded(), published(), visible(), reply], async (run, calls, summary) => {
      await assert.rejects(run, /SideQuest notification failed/);
      assert.ok((await summary()).includes('Generic-Vr-Platform.apk'));
    });
  }
});

test('manual build can publish APK without changing the SideQuest listing', async () => {
  await fixture({ NOTIFY_SIDEQUEST: 'false' }, [created(), uploaded(), published(), visible()], async (run, calls) => {
    await run();
    assert.equal(calls.length, 4);
  });
});
