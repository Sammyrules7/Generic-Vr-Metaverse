#!/usr/bin/env node
// Keep credentials out of command lines, responses, and exception messages.
import { createReadStream } from 'node:fs';
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
  if (!apk || !/^\d+$/.test(code) || !version || !server || !repo) {
    throw new Error('Missing Quest build identity');
  }
  const token = env.FORGEJO_PACKAGE_TOKEN || env.FORGEJO_TOKEN || env.GITHUB_TOKEN;
  if (!token) throw new Error('Forgejo package upload credential is missing');
  const owner = repo.split('/')[0];
  const url = `${server}/api/packages/${encodeURIComponent(owner)}/generic/Generic-Vr-Platform/${encodeURIComponent(version)}/Generic-Vr-Platform.apk`;
  const size = (await stat(apk)).size;
  const uploaded = await request(url, {
    method: 'PUT', redirect: 'error', duplex: 'half',
    headers: { Authorization: `token ${token}`, 'Content-Type': 'application/vnd.android.package-archive', 'Content-Length': String(size) },
    body: createReadStream(apk), signal: AbortSignal.timeout(600000),
  });
  if (uploaded.status !== 201) {
    throw new Error(`Forgejo APK upload failed (HTTP ${uploaded.status}); package:write permission is required`);
  }
  // SideQuest must be able to fetch the APK without our credentials.
  const available = await request(url, { method: 'HEAD', redirect: 'error', signal: AbortSignal.timeout(30000) });
  if (!available.ok || Number(available.headers.get('content-length')) !== size) {
    throw new Error('Published APK is not publicly downloadable; check Forgejo package visibility');
  }
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
