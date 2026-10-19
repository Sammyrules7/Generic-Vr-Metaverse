import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { report } from '../report_web_preview.mjs';
import { publish } from '../publish_desktop.mjs';

const identity = { GITHUB_SERVER_URL: 'https://internal-forgejo',
  GITHUB_REPOSITORY: 'owner/project', GITHUB_TOKEN: 'test-token',
  GITHUB_SHA: 'a'.repeat(40), BUILD_COMMIT: 'b'.repeat(40),
  GITHUB_RUN_ID: '42', GITHUB_RUN_NUMBER: '27', GITHUB_REF_NAME: 'feature', BUILD_SLUG: 'pr-7' };

test('PR status opens the actual built commit only after successful publication', async () => {
  for (const result of ['pending', 'success', 'failure', 'cancelled']) {
    await report({ ...identity, PREVIEW_STATUS: result }, async (url, options) => {
      assert.ok(url.endsWith(`/statuses/${identity.BUILD_COMMIT}`));
      const body = JSON.parse(options.body);
      assert.equal(body.context, 'preview/web');
      assert.equal(body.target_url, result === 'success'
        ? `https://app.vr.maio-tech.com/pr-7/${identity.BUILD_COMMIT}/`
        : 'https://forgejo.maio-tech.com/owner/project/actions/runs/27');
      assert.equal(body.state, result === 'cancelled' ? 'error' : result);
      return new Response(null, { status: 201 });
    });
  }
});

test('status API rejection fails without exposing credentials or response body', async () => {
  await assert.rejects(report({ ...identity, PREVIEW_STATUS: 'success' },
    async () => new Response('private body', { status: 403 })), /HTTP 403/);
});

test('desktop release stays draft until both archives upload, including branch builds', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'desktop-publish-'));
  try {
    for (const platform of ['linux', 'windows']) {
      await writeFile(join(directory, `Generic-Vr-Platform-${platform}.tar.gz`), 'archive');
    }
    for (const failUpload of [false, true]) {
      const calls = [];
      const run = () => publish({ ...identity, EXPORT_DIR: directory }, async (url, options) => {
        calls.push(options.method);
        if (calls.length === 1) {
          const body = JSON.parse(options.body);
          assert.equal(body.prerelease, true);
          assert.equal(body.draft, true);
          assert.equal(body.target_commitish, identity.GITHUB_SHA);
          return Response.json({ id: 12 }, { status: 201 });
        }
        if (options.method === 'PATCH') {
          assert.equal(calls.length, 4);
          assert.deepEqual(JSON.parse(options.body), { draft: false });
          return new Response(null, { status: 200 });
        }
        assert.equal(options.body.get('attachment').size, 7);
        if (failUpload && calls.length === 3) return new Response(null, { status: 403 });
        return Response.json({ browser_download_url: `https://forgejo.maio-tech.com/download/${calls.length}` }, { status: 201 });
      });
      if (failUpload) {
        await assert.rejects(run(), /remains a draft/);
        assert.deepEqual(calls, ['POST', 'POST', 'POST']);
      } else {
        await run();
        assert.deepEqual(calls, ['POST', 'POST', 'POST', 'PATCH']);
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
