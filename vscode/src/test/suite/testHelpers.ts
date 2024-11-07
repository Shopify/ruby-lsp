/* eslint-disable no-process-env */

import os from "os";
import fs from "fs";
import path from "path";

import * as vscode from "vscode";

import { ManagerIdentifier } from "../../ruby";
import { RUBY_VERSION } from "../rubyVersion";

export async function ensureRubyInstallationPaths() {
  const [major, minor, _patch] = RUBY_VERSION.split(".");
  // Ensure that we're activating the correct Ruby version on CI
  if (process.env.CI) {
    if (os.platform() === "linux") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else if (os.platform() === "darwin") {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.Chruby },
          true,
        );

      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(
        `/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64`,
        path.join(os.homedir(), ".rubies", RUBY_VERSION),
      );
    } else {
      await vscode.workspace
        .getConfiguration("rubyLsp")
        .update(
          "rubyVersionManager",
          { identifier: ManagerIdentifier.RubyInstaller },
          true,
        );

      fs.symlinkSync(
        path.join(
          "C:",
          "hostedtoolcache",
          "windows",
          "Ruby",
          RUBY_VERSION,
          "x64",
        ),
        path.join("C:", `Ruby${major}${minor}-${os.arch()}`),
      );
    }
  }
}
