#!/usr/bin/env node
// Keep credentials out of command lines, responses, and exception messages.
import { openAsBlob } from 'node:fs';
import { stat, appendFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export function versionWebhook(raw, code) {
  const url = new URL(raw);
  if (url.protocol !== 'https:' || url.username || url.password ||
      !['sidequestvr.com', 'api.sidequestvr.com'].includes(url.hostname)) {
    throw new Error('SideQuest webhook must use HTTPS on a SideQuest host');
  }
  // The integrations page supplies release-webhook/<token>. The direct APK
  // endpoint takes version-webhook/<Android versionCode>/<token> instead.
  if (url.pathname.includes('/release-webhook/')) {
    url.pathname = url.pathname.replace('/release-webhook/', `/version-webhook/${code}/`);
  } else if (/\/version-webhook\/\d+\//.test(url.pathname)) {
    url.pathname = url.pathname.replace(/\/version-webhook\/\d+\//, `/version-webhook/${code}/`);
  } else {
    throw new Error('Unrecognized SideQuest webhook path; confirm it in the developer portal');
  }
  return url;
}

export async function publish(env = process.env, request = fetch) {
  const { APK_PATH: apk, VERSION_CODE: code, VERSION_NAME: version,
    GITHUB_SERVER_URL: server, GITHUB_REPOSITORY: repo } = env;
  if (!apk || !/^\d+$/.test(code) || !version || !server || !repo || !/^[0-9a-f]{40}$/.test(env.GITHUB_SHA)) {
    throw new Error('Missing Quest build identity');
  }
  const token = env.FORGEJO_TOKEN || env.GITHUB_TOKEN;
  if (!token) throw new Error('Forgejo repository upload credential is missing');
  const api = `${server}/api/v1/repos/${repo}/releases`;
  const headers = { Authorization: `token ${token}`, 'Content-Type': 'application/json' };
  const created = await request(api, {
    method: 'POST', redirect: 'error', headers,
    body: JSON.stringify({ tag_name: `quest-v${version}`, target_commitish: env.GITHUB_SHA,
      name: `Generic-Vr-Platform ${version}`, draft: true,
      prerelease: env.GITHUB_REF_NAME !== 'main',
      body: `Signed Quest APK. Android versionCode: ${code}. Commit: ${env.GITHUB_SHA}.` }),
    signal: AbortSignal.timeout(30000),
  });
  if (created.status !== 201) throw new Error(`Forgejo draft release failed (HTTP ${created.status})`);
  const release = await created.json();
  const size = (await stat(apk)).size;
  const form = new FormData();
  form.set('attachment', await openAsBlob(apk), 'Generic-Vr-Platform.apk');
  const uploaded = await request(`${api}/${release.id}/assets?name=Generic-Vr-Platform.apk`, {
    method: 'POST', redirect: 'error',
    headers: { Authorization: `token ${token}` }, body: form,
    signal: AbortSignal.timeout(600000),
  });
  if (uploaded.status !== 201) throw new Error(`Forgejo APK upload failed (HTTP ${uploaded.status}); release remains a draft`);
  const asset = await uploaded.json();
  const url = asset.browser_download_url;
  if (!url || new URL(url).origin !== new URL(server).origin) throw new Error('Forgejo returned an unexpected APK download origin');
  const published = await request(`${api}/${release.id}`, {
    method: 'PATCH', redirect: 'error', headers, body: JSON.stringify({ draft: false }),
    signal: AbortSignal.timeout(30000),
  });
  if (!published.ok) throw new Error(`Forgejo release publication failed (HTTP ${published.status})`);
  // A ranged, anonymous GET also works if storage redirects to a GET-signed URL.
  const available = await request(url, { method: 'GET', redirect: 'follow',
    headers: { Range: 'bytes=0-0' }, signal: AbortSignal.timeout(30000) });
  const validSize = available.status === 206
    ? available.headers.get('content-range') === `bytes 0-0/${size}`
    : available.status === 200 && Number(available.headers.get('content-length')) === size;
  await available.body?.cancel();
  if (!validSize) throw new Error('Published APK is not publicly downloadable; check the release visibility');
  console.log(`Quest APK: ${url}`);
  if (env.GITHUB_STEP_SUMMARY) {
    await appendFile(env.GITHUB_STEP_SUMMARY, `\nQuest APK: [Generic-Vr-Platform ${version}](${url})\n\nAndroid versionCode: ${code}\n`);
  }
  if (env.NOTIFY_SIDEQUEST !== 'true') return;
  if (!env.SIDEQUEST_WEBHOOK_URL) throw new Error('Set the SIDEQUEST_WEBHOOK_URL repository secret before enabling SideQuest notification');
  const endpoint = versionWebhook(env.SIDEQUEST_WEBHOOK_URL, code);
  const response = await request(endpoint, {
    method: 'POST', redirect: 'error',
    headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }),
    signal: AbortSignal.timeout(60000),
  });
  // Some retired endpoints return 200 with an error body. Never print it:
  // providers may echo the private webhook URL back in their response.
  const body = (await response.text()).trim();
  if (!response.ok || /^(no!|error|gone|invalid|unauthori[sz]ed)/i.test(body)) {
    throw new Error(`SideQuest notification failed (HTTP ${response.status}); the APK is still available above. Check the webhook in the developer portal`);
  }
  console.log('SideQuest webhook accepted the request; verify the version on the listing.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  publish().catch(error => {
    // Fetch error causes can contain the credential-bearing request URL.
    console.error(error instanceof TypeError ? 'Quest publishing network request failed' : error.message);
    process.exitCode = 1;
  });
}
