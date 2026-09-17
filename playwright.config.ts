import { defineConfig } from "@playwright/test";
import path from "node:path";
export default defineConfig({
  testDir: "./tests",
  testMatch: "e2e.spec.ts",
  workers: 1,
  timeout: 45000,
  use: {
    baseURL: "http://127.0.0.1:3101",
    viewport: { width: 1440, height: 1000 },
  },
  webServer: {
    command: "npm start -- --port 3101",
    url: "http://127.0.0.1:3101",
    reuseExistingServer: false,
    env: { CONTENT_DIR: path.resolve("work/e2e-content") },
    timeout: 60000,
  },
});
