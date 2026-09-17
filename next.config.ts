import type { NextConfig } from "next";
const config: NextConfig = {
  serverExternalPackages: ["sharp"],
  outputFileTracingExcludes: {
    "/*": [
      "./content/**/*",
      "./work/**/*",
      "./outputs/**/*",
      "./examples/**/*",
      "./tests/**/*",
    ],
  },
};
export default config;
