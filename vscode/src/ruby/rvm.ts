/* eslint-disable no-process-env */
import os from "os";
import path from "path";

import * as vscode from "vscode";

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

    const installationPath = await this.findRvmInstallation();

    const result = await asyncExec(
      `${installationPath.fsPath} -W0 -rjson -e '${activationScript}'`,
      {
        cwd: this.bundleUri.fsPath,
      },
    );

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

  async findRvmInstallation(): Promise<vscode.Uri> {
    const possiblePaths = [
      vscode.Uri.joinPath(
        vscode.Uri.file(os.homedir()),
        ".rvm",
        "bin",
        "rvm-auto-ruby",
      ),
      vscode.Uri.joinPath(
        vscode.Uri.file("/"),
        "usr",
        "local",
        "rvm",
        "bin",
        "rvm-auto-ruby",
      ),
    ];

    for (const uri of possiblePaths) {
      try {
        await vscode.workspace.fs.stat(uri);
        return uri;
      } catch (_error: any) {
        // Continue to the next installation path
      }
    }

    throw new Error(
      `Cannot find RVM installation directory. Searched in ${possiblePaths.map((uri) => uri.fsPath).join(",")}`,
    );
  }
}
