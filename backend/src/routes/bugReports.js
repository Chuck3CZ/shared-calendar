import { Router } from "express";
import { randomUUID } from "node:crypto";
import { db } from "../db.js";
import { notifyAdmins } from "../notifications.js";

export const bugReportsRouter = Router();

const insertBugReport = db.prepare(`
  INSERT INTO bug_reports (id, user_id, description, app_version, os_version, device_model)
  VALUES (?, ?, ?, ?, ?, ?)
`);

// POST /bug-reports — the shake-to-report gesture. No requireUser: a bug
// can happen before someone's ever signed in, and the report shouldn't be
// blocked on that.
bugReportsRouter.post("/", (req, res) => {
  const { description, app_version, os_version, device_model } = req.body;
  if (!description || !description.trim()) {
    return res.status(400).json({ error: "description is required" });
  }

  const id = randomUUID();
  insertBugReport.run(id, req.user?.id ?? null, description.trim(), app_version ?? null, os_version ?? null, device_model ?? null);

  notifyAdmins({
    title: "Nový bug report",
    body: description.trim().slice(0, 120),
    data: {},
  }).catch((error) => console.error("bug-report push failed:", error));

  res.status(201).json({ id });
});
