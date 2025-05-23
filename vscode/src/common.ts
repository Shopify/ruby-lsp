import { exec } from "child_process";
import { createHash } from "crypto";
import { promisify } from "util";

import * as vscode from "vscode";
import { State } from "vscode-languageclient";

export enum Command {
  Start = "rubyLsp.start",
  Stop = "rubyLsp.stop",
  ShowServerChangelog = "rubyLsp.showServerChangelog",
  Restart = "rubyLsp.restart",
  Update = "rubyLsp.update",
  ToggleExperimentalFeatures = "rubyLsp.toggleExperimentalFeatures",
  ServerOptions = "rubyLsp.serverOptions",
  SelectVersionManager = "rubyLsp.selectRubyVersionManager",
  ToggleFeatures = "rubyLsp.toggleFeatures",
  FormatterHelp = "rubyLsp.formatterHelp",
  RunTest = "rubyLsp.runTest",
  RunTestInTerminal = "rubyLsp.runTestInTerminal",
  DebugTest = "rubyLsp.debugTest",
  ShowSyntaxTree = "rubyLsp.showSyntaxTree",
  DiagnoseState = "rubyLsp.diagnoseState",
  DisplayAddons = "rubyLsp.displayAddons",
  RunTask = "rubyLsp.runTask",
  BundleInstall = "rubyLsp.bundleInstall",
  OpenFile = "rubyLsp.openFile",
  FileOperation = "rubyLsp.fileOperation",
  RailsGenerate = "rubyLsp.railsGenerate",
  RailsDestroy = "rubyLsp.railsDestroy",
  NewMinitestFile = "rubyLsp.newMinitestFile",
  CollectRubyLspInfo = "rubyLsp.collectRubyLspInfo",
  StartServerInDebugMode = "rubyLsp.startServerInDebugMode",
  ShowOutput = "rubyLsp.showOutput",
  MigrateLaunchConfiguration = "rubyLsp.migrateLaunchConfiguration",
  GoToRelevantFile = "rubyLsp.goToRelevantFile",
}

export interface RubyInterface {
  error: boolean;
  versionManager: { identifier: string };
  rubyVersion?: string;
}

export interface Addon {
  name: string;
  errored: boolean;
  // Older versions of ruby-lsp don't return version for add-ons requests
  version?: string;
}

export interface ClientInterface {
  state: State;
  formatter: string;
  addons?: Addon[];
  serverVersion?: string;
  degraded: boolean;
  sendRequest<T>(
    method: string,
    param: any,
    token?: vscode.CancellationToken,
  ): Promise<T>;
}

export interface WorkspaceInterface {
  ruby: RubyInterface;
  lspClient?: ClientInterface;
  error: boolean;
}

// Event emitter used to signal that the language status items need to be refreshed
export const STATUS_EMITTER = new vscode.EventEmitter<
  WorkspaceInterface | undefined
>();

export const asyncExec = promisify(exec);
export const LSP_NAME = "Ruby LSP";
export const LOG_CHANNEL = vscode.window.createOutputChannel(LSP_NAME, {
  log: true,
});
export const SUPPORTED_LANGUAGE_IDS = ["ruby", "erb"];

// A list of feature flags where the key is the name and the value is the rollout percentage.
//
// Note: names added here should also be added to the `rubyLsp.optedOutFeatureFlags` enum in the `package.json` file
// Note 2: -1 is a special value used to indicate under development features. Those can only be enabled explicitly and
// are not impacted by the user's choice of opting into all flags
export const FEATURE_FLAGS = {
  tapiocaAddon: 1.0,
  launcher: 0.1,
  fullTestDiscovery: 0.3,
};

type FeatureFlagConfigurationKey = keyof typeof FEATURE_FLAGS | "all";

// Creates a debounced version of a function with the specified delay. If the function is invoked before the delay runs
// out, then the previous invocation of the function gets cancelled and a new one is scheduled.
//
// Example:
// ```typescript
// // Invoking debouncedFoo will only execute after a second has passed since the last of all invocations
// const debouncedFoo = debounce(this.foo.bind(this), 1000);
// ```
export function debounce(fn: (...args: any[]) => Promise<void>, delay: number) {
  let timeoutID: NodeJS.Timeout | null = null;

  return function (...args: any[]) {
    if (timeoutID) {
      clearTimeout(timeoutID);
    }

    return new Promise((resolve, reject) => {
      timeoutID = setTimeout(() => {
        fn(...args)
          .then((result) => resolve(result))
          .catch((error) => reject(error));
      }, delay);
    });
  };
}

// Check if the given feature is enabled for the current user given the configured rollout percentage
export function featureEnabled(feature: keyof typeof FEATURE_FLAGS): boolean {
  const flagConfiguration = vscode.workspace
    .getConfiguration("rubyLsp")
    .get<
      Record<FeatureFlagConfigurationKey, boolean | undefined>
    >("featureFlags")!;

  // If the user opted out of this feature, return false. We explicitly check for `false` because `undefined` means
  // nothing was configured
  if (flagConfiguration[feature] === false || flagConfiguration.all === false) {
    return false;
  }

  const percentage = FEATURE_FLAGS[feature];

  // If the user opted-in to all features, return true
  if (
    (flagConfiguration.all && percentage !== -1) ||
    flagConfiguration[feature]
  ) {
    return true;
  }

  const machineId = vscode.env.machineId;
  // Create a digest of the concatenated machine ID and feature name, which will generate a unique hash for this
  // user-feature combination
  const hash = createHash("sha256")
    .update(`${machineId}-${feature}`)
    .digest("hex");

  // Convert the first 8 characters of the hash to a number between 0 and 1
  const hashNum = parseInt(hash.substring(0, 8), 16) / 0xffffffff;

  // If that number is below the percentage, then the feature is enabled for this user
  return hashNum < percentage;
}
