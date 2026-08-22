import express from "express";
import { identify } from "./identity.js";
import { eventsRouter } from "./routes/events.js";
import { adminRouter } from "./routes/admin.js";

const app = express();
app.use(express.json());
app.use(identify);

app.get("/health", (req, res) => res.json({ ok: true }));
app.use("/events", eventsRouter);
app.use("/admin", adminRouter);

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`shared-calendar backend listening on :${port}`));
