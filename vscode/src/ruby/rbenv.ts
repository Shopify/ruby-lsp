/* eslint-disable no-process-env */

import path from "path";

import { asyncExec } from "../common";

import { VersionManager, ActivationResult } from "./versionManager";

// Seamlessly manage your app’s Ruby environment with rbenv.
//
// Learn more: https://github.com/rbenv/rbenv
export class Rbenv extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript = [
      "STDERR.print(",
      "{env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION,home:Gem.user_dir,default:Gem.default_dir}",
      ".to_json)",
    ].join("");

    const result = await asyncExec(
      `rbenv exec ruby -W0 -rjson -e '${activationScript}'`,
      {
        cwd: this.bundleUri.fsPath,
      },
    );

    const parsedResult = JSON.parse(result.stderr);

    // The addition of GEM_HOME, GEM_PATH and putting the bin directories into the PATH happens through Rbenv's shell
    // hooks. Since we want to avoid spawning shells due to integration issues, we need to insert these variables
    // ourselves, so that gem executables can be properly found
    parsedResult.env.GEM_HOME = parsedResult.home;
    parsedResult.env.GEM_PATH = `${parsedResult.home}${path.delimiter}${parsedResult.default}`;
    parsedResult.env.PATH = [
      path.join(parsedResult.home, "bin"),
      path.join(parsedResult.default, "bin"),
      parsedResult.env.PATH,
    ].join(path.delimiter);

    return {
      env: { ...process.env, ...parsedResult.env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }
}
