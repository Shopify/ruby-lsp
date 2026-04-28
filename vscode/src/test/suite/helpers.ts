import path from "path";
import os from "os";
import fs from "fs";

import * as vscode from "vscode";
import sinon from "sinon";

import { MAJOR, MINOR, RUBY_VERSION } from "../rubyVersion";

export function createRubySymlinks() {
  if (os.platform() === "linux") {
    const linkPath = path.join(os.homedir(), ".rubies", RUBY_VERSION);

    if (!fs.existsSync(linkPath)) {
      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(`/opt/hostedtoolcache/Ruby/${RUBY_VERSION}/x64`, linkPath);
    }
  } else if (os.platform() === "darwin") {
    const linkPath = path.join(os.homedir(), ".rubies", RUBY_VERSION);

    if (!fs.existsSync(linkPath)) {
      fs.mkdirSync(path.join(os.homedir(), ".rubies"), { recursive: true });
      fs.symlinkSync(`/Users/runner/hostedtoolcache/Ruby/${RUBY_VERSION}/arm64`, linkPath);
    }
  } else {
    const linkPath = path.join("C:", `Ruby${MAJOR}${MINOR}-${os.arch()}`);

    if (!fs.existsSync(linkPath)) {
      fs.symlinkSync(path.join("C:", "hostedtoolcache", "windows", "Ruby", RUBY_VERSION, "x64"), linkPath);
    }
  }
}

class FakeWorkspaceState implements vscode.Memento {
  private store: Record<string, any> = {};

  keys(): ReadonlyArray<string> {
    return Object.keys(this.store);
  }

  get<T>(key: string): T | undefined {
    return this.store[key];
  }

  update(key: string, value: any): Thenable<void> {
    this.store[key] = value;
    return Promise.resolve();
  }
}

export const LSP_WORKSPACE_PATH = path.dirname(path.dirname(path.dirname(path.dirname(__dirname))));
export const LSP_WORKSPACE_URI = vscode.Uri.file(LSP_WORKSPACE_PATH);
export const LSP_WORKSPACE_FOLDER: vscode.WorkspaceFolder = {
  uri: LSP_WORKSPACE_URI,
  name: path.basename(LSP_WORKSPACE_PATH),
  index: 0,
};

export type FakeContext = vscode.ExtensionContext & { dispose: () => void };

// Stubs `vscode.workspace.getConfiguration` so that requested keys return stubbed values, while any unspecified keys
// (or unspecified sections) fall through to the real configuration
export function stubWorkspaceConfiguration(
  sandbox: sinon.SinonSandbox,
  stubs: Record<string, Record<string, unknown>>,
): sinon.SinonStub {
  const original = vscode.workspace.getConfiguration.bind(vscode.workspace);

  return sandbox
    .stub(vscode.workspace, "getConfiguration")
    .callsFake((section?: string, scope?: vscode.ConfigurationScope | null) => {
      const real = original(section, scope);
      const sectionStubs = stubs[section ?? ""];

      if (!sectionStubs) {
        return real;
      }

      // Can't Proxy a WorkspaceConfiguration: VS Code defines `get` as non-configurable + non-writable, which
      // violates Proxy invariants. Instead, build a delegating object that overrides `get` and forwards everything
      // else to the real configuration (preserving `this` via bind so private state access still works).
      const wrapper: vscode.WorkspaceConfiguration = {
        get(key: string, defaultValue?: unknown) {
          if (key in sectionStubs) {
            return sectionStubs[key];
          }
          return defaultValue === undefined ? real.get(key) : real.get(key, defaultValue);
        },
        has: real.has.bind(real),
        inspect: real.inspect.bind(real),
        update: real.update.bind(real),
      };

      return wrapper;
    });
}

export function createContext() {
  const subscriptions: vscode.Disposable[] = [];

  return {
    extensionMode: vscode.ExtensionMode.Test,
    subscriptions,
    workspaceState: new FakeWorkspaceState(),
    extensionUri: vscode.Uri.joinPath(LSP_WORKSPACE_URI, "vscode"),
    dispose: () => {
      subscriptions.forEach((subscription) => subscription.dispose());
    },
  } as unknown as FakeContext;
}
