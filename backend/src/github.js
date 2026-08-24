const GITHUB_API = "https://api.github.com";

/**
 * Files a bug report as a GitHub issue. Best-effort: without GITHUB_TOKEN
 * and GITHUB_REPO configured, bug reports still work fine (they just stay
 * app-only), so this returns null rather than throwing when unconfigured.
 */
export async function createGithubIssue({ description, reporterName, appVersion, osVersion, deviceModel }) {
  const token = process.env.GITHUB_TOKEN;
  const repo = process.env.GITHUB_REPO;
  if (!token || !repo) return null;

  const bodyLines = [description, "", "---", `Nahlásil: ${reporterName ?? "Nepřihlášený"}`];
  if (appVersion) bodyLines.push(`Verze appky: ${appVersion}`);
  if (deviceModel || osVersion) bodyLines.push(`Zařízení: ${deviceModel ?? "?"} · iOS ${osVersion ?? "?"}`);

  const title = description.length > 80 ? `${description.slice(0, 77)}...` : description;

  const response = await fetch(`${GITHUB_API}/repos/${repo}/issues`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "Content-Type": "application/json",
      "User-Agent": "SharedCalendar-bug-reports",
    },
    body: JSON.stringify({ title, body: bodyLines.join("\n"), labels: ["bug-report"] }),
  });

  if (!response.ok) {
    throw new Error(`GitHub issue creation failed: ${response.status} ${await response.text()}`);
  }

  const issue = await response.json();
  return { number: issue.number, url: issue.html_url };
}
