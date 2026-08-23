import express from "express";
import { identify } from "./identity.js";
import { eventsRouter } from "./routes/events.js";
import { adminRouter } from "./routes/admin.js";
import { meRouter } from "./routes/me.js";
import { authRouter } from "./routes/auth.js";
import { startNotificationScheduler } from "./notifications.js";
import { universalLinksRouter } from "./routes/universalLinks.js";
import { bugReportsRouter } from "./routes/bugReports.js";

const app = express();
app.use(express.json());
app.use(identify);

app.get("/health", (req, res) => res.json({ ok: true }));
app.use("/events", eventsRouter);
app.use("/admin", adminRouter);
app.use("/me", meRouter);
app.use("/auth", authRouter);
app.use(universalLinksRouter);
app.use("/bug-reports", bugReportsRouter);

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`shared-calendar backend listening on :${port}`));
startNotificationScheduler();
