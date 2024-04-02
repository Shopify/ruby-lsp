/* eslint-disable no-process-env */
import os from "os";
import path from "path";

import { asyncExec } from "../common";

import { ActivationResult, VersionManager } from "./versionManager";

// Ruby enVironment Manager. It manages Ruby application environments and enables switching between them.
// Learn more:
// - https://github.com/rvm/rvm
// - https://rvm.io
export class Rvm extends VersionManager {
  async activate(): Promise<ActivationResult> {
    const activationScript = [
      "STDERR.print(",
      "{yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION,",
      "home:Gem.user_dir,default:Gem.default_dir,ruby:RbConfig.ruby}",
      ".to_json)",
    ].join("");

    const basePaths = [
      path.join(os.homedir(), ".rvm", "bin"),
      "/usr/local/rvm/bin",
      "/usr/share/rvm/bin",
    ];
    // check if rvm-auto-ruby is in the PATH
    try {
      const pathCheck = await asyncExec("which rvm-auto-ruby");
      this.outputChannel.info(`Output check: ${pathCheck.stdout}`);
      if (pathCheck.stdout.includes("rvm-auto-ruby")) {
        // rvm-auto-ruby is in the PATH variable
        basePaths.unshift("");
      }
    } catch (error) {
      const pathOutput = await asyncExec("echo $PATH");
      this.outputChannel.info(
        `Could not find rvm-auto-ruby on PATH: ${error}, current PATH: ${pathOutput.stdout}`,
      );
    }

    let result = { stderr: "" };
    for (const basePath of basePaths) {
      try {
        const resultOfPath = await asyncExec(
          `${path.join(basePath, "rvm-auto-ruby")} -W0 -rjson -e '${activationScript}'`,
          {
            cwd: this.bundleUri.fsPath,
          },
        );
        result = resultOfPath;
        this.outputChannel.info(
          `Activated rvm env with this path: ${path.join(basePath, "rvm-auto-ruby")}`,
        );
        break;
      } catch (error) {
        this.outputChannel.info(
          `Checking if we can activate rvm env with this path: ${path.join(basePath, "rvm-auto-ruby")}`,
        );
      }
    }

    if (result.stderr === "") {
      this.outputChannel.error(
        `Could not activate rvm based environment with these paths: ${basePaths.join(", ")}`,
      );
      return { error: true };
    }
    const parsedResult = JSON.parse(result.stderr);

    // Invoking `rvm-auto-ruby` doesn't actually inject anything into the environment, it just finds the right Ruby to
    // execute. We need to build the environment from the variables we return in the activation script
    const env = {
      GEM_HOME: parsedResult.home,
      GEM_PATH: `${parsedResult.home}${path.delimiter}${parsedResult.default}`,
      PATH: [
        path.join(parsedResult.home, "bin"),
        path.join(parsedResult.default, "bin"),
        path.dirname(parsedResult.ruby),
        process.env.PATH,
      ].join(path.delimiter),
    };

    const activatedKeys = Object.entries(env)
      .map(([key, value]) => `${key}=${value}`)
      .join(" ");

    this.outputChannel.info(`Activated Ruby environment: ${activatedKeys}`);

    return {
      env: { ...process.env, ...env },
      yjit: parsedResult.yjit,
      version: parsedResult.version,
    };
  }
}
