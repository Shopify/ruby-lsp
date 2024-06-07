/* eslint-disable no-process-env */

import { VersionManager, ActivationResult } from "./versionManager";

// Seamlessly manage your app’s Ruby environment with rbenv.
//
// Learn more: https://github.com/rbenv/rbenv
export class Rbenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript =
      "STDERR.print({env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION}.to_json)";

    const result = await this.runScript(
      `rbenv exec ruby -W0 -rjson -e '${activationScript}'`,
    );

    const parsedResult = this.parseWithErrorHandling(result.stderr);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }
}
