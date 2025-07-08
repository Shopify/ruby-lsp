/* eslint-disable no-process-env */
import os from "os";

import * as vscode from "vscode";

import { Chruby } from "./chruby";

interface RubyVersion {
  engine?: string;
  version: string;
}

// Most version managers do not support Windows. One popular way of installing Ruby on Windows is via RubyInstaller,
// which places the rubies in directories like C:\Ruby32-x64 (i.e.: Ruby{major}{minor}-{arch}). To automatically switch
// Ruby versions on Windows, we use the same mechanism as Chruby to discover the Ruby version based on `.ruby-version`
// files and then try to search the directories commonly used by RubyInstaller.
//
// If we can't find it there, then we throw an error and rely on the user to manually select where Ruby is installed.
export class RubyInstaller extends Chruby {
  // Environment variables are case sensitive on Windows when we access them through NodeJS. We need to ensure that
  // we're searching through common variations, so that we don't accidentally miss the path we should inherit
  protected getProcessPath() {
    return process.env.Path ?? process.env.PATH ?? process.env.path;
  }

  // Returns the full URI to the Ruby executable
  protected async findRubyUri(rubyVersion: RubyVersion): Promise<vscode.Uri> {
    const [major, minor, _patch] = rubyVersion.version.split(".").map(Number);

    const possibleInstallationUris = [
      vscode.Uri.joinPath(vscode.Uri.file("C:"), `Ruby${major}${minor}-${os.arch()}`),
      vscode.Uri.joinPath(vscode.Uri.file(os.homedir()), `Ruby${major}${minor}-${os.arch()}`),
    ];

    for (const installationUri of possibleInstallationUris) {
      try {
        await vscode.workspace.fs.stat(installationUri);
        return vscode.Uri.joinPath(installationUri, "bin", "ruby");
      } catch (_error: any) {
        // Continue searching
      }
    }

    throw new Error(
      `Cannot find installation directory for Ruby version ${rubyVersion.version}.\
         Searched in ${possibleInstallationUris.map((uri) => uri.fsPath).join(", ")}`,
    );
  }

  protected async runActivationScript(
    rubyExecutableUri: vscode.Uri,
    rubyVersion: RubyVersion,
  ): Promise<{
    defaultGems: string;
    gemHome: string;
    yjit: boolean;
    version: string;
  }> {
    const activationResult = await super.runActivationScript(rubyExecutableUri, rubyVersion);

    activationResult.gemHome = activationResult.gemHome.replace(/\//g, "\\");
    activationResult.defaultGems = activationResult.defaultGems.replace(/\//g, "\\");

    return activationResult;
  }
}
