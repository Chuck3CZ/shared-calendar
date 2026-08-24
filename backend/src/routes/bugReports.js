import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { notifyAdmins } from "../notifications.js";
import { createGithubIssue } from "../github.js";

export const bugReportsRouter = Router();

const insertBugReport = db.prepare(`
  INSERT INTO bug_reports (id, user_id, description, app_version, os_version, device_model)
  VALUES (?, ?, ?, ?, ?, ?)
`);
const setGithubIssue = db.prepare(
  "UPDATE bug_reports SET github_issue_number = ?, github_issue_url = ? WHERE id = ?"
);

// POST /bug-reports — the shake-to-report gesture. No requireUser: a bug
// can happen before someone's ever signed in, and the report shouldn't be
// blocked on that.
bugReportsRouter.post("/", (req, res) => {
  const { description, app_version, os_version, device_model } = req.body;
  if (!description || !description.trim()) {
    return res.status(400).json({ error: "description is required" });
  }

  const id = randomUUID();
  const trimmed = description.trim();
  insertBugReport.run(id, req.user?.id ?? null, trimmed, app_version ?? null, os_version ?? null, device_model ?? null);

  notifyAdmins({
    title: "Nový bug report",
    body: trimmed.slice(0, 120),
    data: { type: "bug_report" },
  }).catch((error) => console.error("bug-report push failed:", error));

  createGithubIssue({
    description: trimmed,
    reporterName: req.user?.display_name ?? null,
    appVersion: app_version,
    osVersion: os_version,
    deviceModel: device_model,
  })
    .then((issue) => {
      if (issue) setGithubIssue.run(issue.number, issue.url, id);
    })
    .catch((error) => console.error("github issue creation failed:", error));

  res.status(201).json({ id });
});
