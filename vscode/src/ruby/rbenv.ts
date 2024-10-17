/* eslint-disable no-process-env */

import { VersionManager, ActivationResult } from "./versionManager";

// Seamlessly manage your app’s Ruby environment with rbenv.
//
// Learn more: https://github.com/rbenv/rbenv
export class Rbenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const parsedResult = await this.runEnvActivationScript("rbenv exec ruby");

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
      gemPath: parsedResult.gemPath,
    };
  }
}
