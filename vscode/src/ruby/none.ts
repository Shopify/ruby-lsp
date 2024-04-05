/* eslint-disable no-process-env */
import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// None
//
// This "version manager" represents the case where no manager is used, but the environment still needs to be inserted
// into the NodeJS process. For example, when you use Docker, install Ruby through Homebrew or use some other mechanism
// to have Ruby available in your PATH automatically.
//
// If you don't have Ruby automatically available in your PATH and are not using a version manager, look into
// configuring custom Ruby activation
export class None extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript =
      "STDERR.print({ env: ENV.to_h, yjit: !!defined?(RubyVM::YJIT), version: RUBY_VERSION }.to_json)";

    const result = await asyncExec(`ruby -W0 -rjson -e '${activationScript}'`, {
      cwd: this.bundleUri.fsPath,
    });

    const parsedResult = JSON.parse(result.stderr);
    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }
}
