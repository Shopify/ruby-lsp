/* eslint-disable no-process-env */
import os from "os";
import path from "path";

import * as vscode from "vscode";

import { asyncExec } from "../common";

import { ActivationResult, VersionManager } from "./versionManager";

interface RubyVersion {
  engine?: string;
  version: string;
}

// A tool to change the current Ruby version
// Learn more: https://github.com/postmodern/chruby
export class Chruby extends VersionManager {
  // Only public so that we can point to a different directory in tests
  public rubyInstallationUris = [
    vscode.Uri.joinPath(vscode.Uri.file("/"), "opt", "rubies"),
    vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), ".rubies"),
  ];

  async activate(): Promise<ActivationResult> {
    const versionInfo = await this.discoverRubyVersion();
    const rubyUri = await this.findRubyUri(versionInfo);
    const { defaultGems, gemHome, yjit } =
      await this.runActivationScript(rubyUri);

    this.outputChannel.info(
      `Activated Ruby environment: defaultGems=${defaultGems} gemHome=${gemHome} yjit=${yjit}`,
    );

    const rubyEnv = {
      GEM_HOME: gemHome,
      GEM_PATH: `${gemHome}${path.delimiter}${defaultGems}`,
      PATH: `${path.join(gemHome, "bin")}${path.delimiter}${path.join(
        defaultGems,
        "bin",
      )}${path.delimiter}${path.dirname(rubyUri.fsPath)}${path.delimiter}${process.env.PATH}`,
    };

    return {
      env: { ...process.env, ...rubyEnv },
      yjit,
      version: versionInfo.version,
    };
  }

  // Returns the full URI to the Ruby executable
  protected async findRubyUri(rubyVersion: RubyVersion): Promise<vscode.Uri> {
    // If an engine was specified in the .ruby-version file, we favor looking for that first and also try just the
    // version number. If no engine was specified, we first try just the version number and then we try using `ruby` as
    // the default engine
    const possibleVersionNames = rubyVersion.engine
      ? [`${rubyVersion.engine}-${rubyVersion.version}`, rubyVersion.version]
      : [rubyVersion.version, `ruby-${rubyVersion.version}`];

    for (const uri of this.rubyInstallationUris) {
      let installationUri: vscode.Uri;

      for (const versionName of possibleVersionNames) {
        try {
          installationUri = vscode.Uri.joinPath(uri, versionName);
          await vscode.workspace.fs.stat(installationUri);
          return vscode.Uri.joinPath(installationUri, "bin", "ruby");
        } catch (_error: any) {
          // Continue to the next version name
        }
      }
    }

    throw new Error(
      `Cannot find installation directory for Ruby version ${possibleVersionNames.join(" or ")}`,
    );
  }

  // Returns the Ruby version information including version and engine. E.g.: ruby-3.3.0, truffleruby-21.3.0
  private async discoverRubyVersion(): Promise<RubyVersion> {
    let uri = this.bundleUri;
    const root = path.parse(uri.fsPath).root;

    while (uri.fsPath !== root) {
      try {
        const rubyVersionUri = vscode.Uri.joinPath(uri, ".ruby-version");
        const content = await vscode.workspace.fs.readFile(rubyVersionUri);
        const version = content.toString().trim();

        if (version === "") {
          throw new Error(`Ruby version file ${rubyVersionUri} is empty`);
        }

        const match =
          /((?<engine>[A-Za-z]+)-)?(?<version>\d\.\d\.\d(-[A-Za-z0-9]+)?)/.exec(
            version,
          );

        if (!match?.groups) {
          throw new Error(
            `Ruby version file ${rubyVersionUri} contains invalid format. Expected (engine-)?version, got ${version}`,
          );
        }

        this.outputChannel.info(
          `Discovered Ruby version ${version} from ${rubyVersionUri.toString()}`,
        );
        return { engine: match.groups.engine, version: match.groups.version };
      } catch (error: any) {
        // If the file doesn't exist, continue going up the directory tree
        uri = vscode.Uri.file(path.dirname(uri.fsPath));
        continue;
      }
    }

    throw new Error("No .ruby-version file was found");
  }

  // Run the activation script using the Ruby installation we found so that we can discover gem paths
  private async runActivationScript(
    rubyExecutableUri: vscode.Uri,
  ): Promise<{ defaultGems: string; gemHome: string; yjit: boolean }> {
    // Typically, GEM_HOME points to $HOME/.gem/ruby/version_without_patch. For example, for Ruby 3.2.2, it would be
    // $HOME/.gem/ruby/3.2.0. However, chruby overrides GEM_HOME to use the patch part of the version, resulting in
    // $HOME/.gem/ruby/3.2.2. In our activation script, we check if a directory using the patch exists and then prefer
    // that over the default one.
    const script = [
      "user_dir = Gem.user_dir",
      "paths = Gem.path",
      "if paths.length > 2",
      "  paths.delete(Gem.default_dir)",
      "  paths.delete(Gem.user_dir)",
      "  if paths[0]",
      "    user_dir = paths[0] if Dir.exist?(paths[0])",
      "  end",
      "end",
      "newer_gem_home = File.join(File.dirname(user_dir), RUBY_VERSION)",
      "gems = (Dir.exist?(newer_gem_home) ? newer_gem_home : user_dir)",
      "data = { defaultGems: Gem.default_dir, gemHome: gems, yjit: !!defined?(RubyVM::YJIT) }",
      "STDERR.print(JSON.dump(data))",
    ].join(";");

    const result = await asyncExec(
      `${rubyExecutableUri.fsPath} -W0 -rjson -e '${script}'`,
      { cwd: this.bundleUri.fsPath },
    );

    return JSON.parse(result.stderr);
  }
}
