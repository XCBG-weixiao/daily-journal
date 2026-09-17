import fs from "node:fs/promises";
await fs.rm("work/e2e-content", { recursive: true, force: true });
await fs.mkdir("work", { recursive: true });
await fs.cp("examples/content", "work/e2e-content", { recursive: true });
