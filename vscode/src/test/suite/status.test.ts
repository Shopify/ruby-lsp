import * as assert from "assert";

import * as vscode from "vscode";
import { beforeEach, afterEach } from "mocha";
import { State } from "vscode-languageclient/node";
import sinon from "sinon";

import { Ruby } from "../../ruby";
import {
  RubyVersionStatus,
  ServerStatus,
  StatusItem,
  FeaturesStatus,
  FormatterStatus,
  AddonsStatus,
} from "../../status";
import { Command, WorkspaceInterface } from "../../common";

suite("StatusItems", () => {
  let ruby: Ruby;
  let status: StatusItem;
  let workspace: WorkspaceInterface;

  afterEach(() => {
    status.dispose();
  });

  suite("RubyVersionStatus", () => {
    beforeEach(() => {
      ruby = {
        rubyVersion: "3.2.0",
        versionManager: { identifier: "shadowenv" },
      } as Ruby;
      workspace = {
        ruby,
        lspClient: {
          addons: [],
          state: State.Running,
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
          degraded: false,
        },
        error: false,
      };
      status = new RubyVersionStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      assert.strictEqual(status.item.text, "Using Ruby 3.2.0 with shadowenv");
      assert.strictEqual(status.item.name, "Ruby Version");
      assert.strictEqual(status.item.command?.title, "Configure");
      assert.strictEqual(
        status.item.command.command,
        Command.SelectVersionManager,
      );
    });

    test("Refresh updates version string", () => {
      assert.strictEqual(status.item.text, "Using Ruby 3.2.0 with shadowenv");

      workspace.ruby.rubyVersion = "3.2.1";
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Using Ruby 3.2.1 with shadowenv");
    });
  });

  suite("ServerStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          state: State.Running,
          addons: [],
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
          degraded: false,
        },
        error: false,
      };
      status = new ServerStatus();
      status.refresh(workspace);
    });

    test("Refresh when server is starting", () => {
      workspace.lspClient!.state = State.Starting;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP: Starting");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Information,
      );
      assert.strictEqual(status.item.name, "Ruby LSP Server Status");
    });

    test("Refresh when server is running", () => {
      workspace.lspClient!.state = State.Running;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP v1.0.0: Running");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Information,
      );
      assert.strictEqual(status.item.name, "Ruby LSP Server Status");
    });

    test("Refresh when server is stopping", () => {
      workspace.lspClient!.state = State.Stopped;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP: Stopped");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Information,
      );
      assert.strictEqual(status.item.name, "Ruby LSP Server Status");
    });

    test("Refresh when server has errored", () => {
      workspace.error = true;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP: Error");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Error,
      );
      assert.strictEqual(status.item.name, "Ruby LSP Server Status");
    });

    test("Refresh when server is in degraded mode", () => {
      workspace.lspClient!.degraded = true;
      status.refresh(workspace);
      assert.strictEqual(
        status.item.text,
        "Ruby LSP v1.0.0: Running (degraded)",
      );
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Warning,
      );
    });
  });

  suite("FeaturesStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          addons: [],
          state: State.Running,
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
          degraded: false,
        },
        error: false,
      };
      status = new FeaturesStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      const features = {
        codeActions: true,
        diagnostics: true,
        documentHighlights: true,
        documentLink: true,
        documentSymbols: true,
        foldingRanges: true,
        formatting: true,
        hover: true,
        inlayHint: true,
        onTypeFormatting: true,
        selectionRanges: true,
        semanticHighlighting: true,
        completion: true,
        codeLens: true,
        definition: true,
        workspaceSymbol: true,
        signatureHelp: true,
        typeHierarchy: true,
      };
      const numberOfFeatures = Object.keys(features).length;
      const stub = sinon.stub(vscode.workspace, "getConfiguration").returns({
        get: () => features,
      } as unknown as vscode.WorkspaceConfiguration);

      assert.strictEqual(
        status.item.text,
        `${numberOfFeatures}/${numberOfFeatures} features enabled`,
      );
      assert.strictEqual(status.item.name, "Ruby LSP Features");
      assert.strictEqual(status.item.command?.title, "Manage");
      assert.strictEqual(status.item.command.command, Command.ToggleFeatures);
      stub.restore();
    });

    test("Refresh updates number of features", () => {
      const features = {
        codeActions: false,
        diagnostics: true,
        documentHighlights: true,
        documentLink: true,
        documentSymbols: true,
        foldingRanges: true,
        formatting: true,
        hover: true,
        inlayHint: true,
        onTypeFormatting: true,
        selectionRanges: true,
        semanticHighlighting: true,
        completion: true,
        codeLens: true,
        definition: true,
        workspaceSymbol: true,
        signatureHelp: true,
      };
      const numberOfFeatures = Object.keys(features).length;
      const stub = sinon.stub(vscode.workspace, "getConfiguration").returns({
        get: () => features,
      } as unknown as vscode.WorkspaceConfiguration);

      status.refresh(workspace);
      assert.strictEqual(
        status.item.text,
        `${numberOfFeatures - 1}/${numberOfFeatures} features enabled`,
      );

      stub.restore();
    });
  });

  suite("FormatterStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          addons: [],
          state: State.Running,
          formatter: "auto",
          serverVersion: "1.0.0",
          degraded: false,
          sendRequest: <T>() => Promise.resolve([] as T),
        },
        error: false,
      };
      status = new FormatterStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      assert.strictEqual(status.item.text, "Formatter: auto");
      assert.strictEqual(status.item.name, "Ruby LSP Formatter");
      assert.strictEqual(status.item.command?.title, "Help");
      assert.strictEqual(status.item.command.command, Command.FormatterHelp);
    });
  });

  suite("AddonsStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          addons: undefined,
          state: State.Running,
          formatter: "auto",
          degraded: false,
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
        },
        error: false,
      };
      status = new AddonsStatus();
      status.refresh(workspace);
    });

    test("Status displays the server requirement info when addons is undefined", () => {
      workspace.lspClient!.addons = undefined;
      status.refresh(workspace);

      assert.strictEqual(
        status.item.text,
        "Addons: requires server to be v0.17.4 or higher to display this field",
      );
      assert.strictEqual(status.item.name, "Ruby LSP Addons");
    });

    test("Status displays no addons when addons is an empty array", () => {
      workspace.lspClient!.addons = [];
      status.refresh(workspace);

      assert.strictEqual(status.item.text, "Addons: none");
      assert.strictEqual(status.item.name, "Ruby LSP Addons");
    });

    test("Status displays addon count and command to list commands", () => {
      workspace.lspClient!.addons = [
        { name: "foo", errored: false },
        { name: "bar", errored: true },
      ];

      status.refresh(workspace);

      assert.strictEqual(status.item.text, "Addons: 2");
      assert.strictEqual(status.item.name, "Ruby LSP Addons");
      assert.strictEqual(status.item.command?.title, "Details");
      assert.strictEqual(status.item.command.command, Command.DisplayAddons);
    });
  });
});
