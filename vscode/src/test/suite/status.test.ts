import * as assert from "assert";

import * as vscode from "vscode";
import { beforeEach, afterEach } from "mocha";
import { State } from "vscode-languageclient/node";
import sinon from "sinon";

import { Ruby } from "../../ruby";
import {
  RubyVersionStatus,
  ServerStatus,
  ExperimentalFeaturesStatus,
  StatusItem,
  FeaturesStatus,
  FormatterStatus,
} from "../../status";
import { Command, WorkspaceInterface } from "../../common";

suite("StatusItems", () => {
  let ruby: Ruby;
  let status: StatusItem;
  let workspace: WorkspaceInterface;
  let formatter: string;

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
          state: State.Running,
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
        },
        error: false,
      };
      status = new RubyVersionStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      assert.strictEqual(status.item.text, "Using Ruby 3.2.0 with shadowenv");
      assert.strictEqual(status.item.name, "Ruby LSP Status");
      assert.strictEqual(status.item.command?.title, "Change version manager");
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
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
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
    });

    test("Refresh when server is running", () => {
      workspace.lspClient!.state = State.Running;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP v1.0.0: Running");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Information,
      );
    });

    test("Refresh when server is stopping", () => {
      workspace.lspClient!.state = State.Stopped;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP: Stopped");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Information,
      );
    });

    test("Refresh when server has errored", () => {
      workspace.error = true;
      status.refresh(workspace);
      assert.strictEqual(status.item.text, "Ruby LSP: Error");
      assert.strictEqual(
        status.item.severity,
        vscode.LanguageStatusSeverity.Error,
      );
    });
  });

  suite("ExperimentalFeaturesStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          state: State.Running,
          formatter,
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
        },
        error: false,
      };
      status = new ExperimentalFeaturesStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      assert.match(status.item.text, /Experimental features (dis|en)abled/);
      assert.strictEqual(status.item.name, "Experimental features");
      assert.match(status.item.command?.title!, /Enable|Disable/);
      assert.strictEqual(
        status.item.command!.command,
        Command.ToggleExperimentalFeatures,
      );
    });
  });

  suite("FeaturesStatus", () => {
    beforeEach(() => {
      ruby = {} as Ruby;
      workspace = {
        ruby,
        lspClient: {
          state: State.Running,
          formatter: "none",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
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
          state: State.Running,
          formatter: "auto",
          serverVersion: "1.0.0",
          sendRequest: <T>() => Promise.resolve([] as T),
        },
        error: false,
      };
      status = new FormatterStatus();
      status.refresh(workspace);
    });

    test("Status is initialized with the right values", () => {
      assert.strictEqual(status.item.text, "Formatter: auto");
      assert.strictEqual(status.item.name, "Formatter");
      assert.strictEqual(status.item.command?.title, "Help");
      assert.strictEqual(status.item.command.command, Command.FormatterHelp);
    });
  });
});
