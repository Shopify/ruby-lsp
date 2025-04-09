import { spawn } from "child_process";
import net from "net";

import * as rpc from "vscode-jsonrpc/node";
import * as vscode from "vscode";

import { Workspace } from "./workspace";
import { LinkedCancellationSource } from "./linkedCancellationSource";

interface TestEventId {
  uri: string;
  id: string;
}
type TestEventWithMessage = TestEventId & { message: string };

// All notification types that may be produce by our custom JSON test reporter
const NOTIFICATION_TYPES = {
  start: new rpc.NotificationType<TestEventId>("start"),
  pass: new rpc.NotificationType<TestEventId>("pass"),
  skip: new rpc.NotificationType<TestEventId>("skip"),
  fail: new rpc.NotificationType<TestEventWithMessage>("fail"),
  error: new rpc.NotificationType<TestEventWithMessage>("error"),
  finish: new rpc.NotificationType<void>("finish"),
};

export enum Mode {
  Run = "run",
  Debug = "debug",
}

// The StreamingRunner class is responsible for executing the test process or launching the debugger while handling the
// streaming events to update the test explorer status
export class StreamingRunner {
  private readonly promises: Promise<void>[] = [];
  private readonly disposables: vscode.Disposable[] = [];
  private readonly run: vscode.TestRun;
  private readonly findTestItem: (
    id: string,
    uri: vscode.Uri,
  ) => Promise<vscode.TestItem | undefined>;

  constructor(
    run: vscode.TestRun,
    findTestItem: (
      id: string,
      uri: vscode.Uri,
    ) => Promise<vscode.TestItem | undefined>,
  ) {
    this.run = run;
    this.findTestItem = findTestItem;
  }

  async execute(
    command: string,
    env: NodeJS.ProcessEnv,
    workspace: Workspace,
    mode: Mode,
    linkedCancellationSource: LinkedCancellationSource,
  ) {
    await new Promise<void>((resolve, reject) => {
      const server = net.createServer();
      server.on("error", reject);
      server.unref();

      server.listen(0, "localhost", async () => {
        const address = server.address();
        const serverPort =
          typeof address === "string" ? address : address?.port.toString();

        if (!serverPort) {
          reject(
            new Error(
              "Failed to set up TCP server to communicate with test process",
            ),
          );
          return;
        }

        const abortController = new AbortController();

        server.on("connection", (socket) => {
          const connection = rpc.createMessageConnection(
            new rpc.StreamMessageReader(socket),
            new rpc.StreamMessageWriter(socket),
          );
          const finalize = () => {
            Promise.all(this.promises)
              .then(() => {
                this.disposables.forEach((disposable) => disposable.dispose());
                connection.end();
                connection.dispose();
                server.close();
                resolve();
              })
              .catch(reject);
          };

          // We resolve the promise and perform cleanup on two occasions: if the test run finished normally, then we
          // should receive the finish event. The other case is when the run is cancelled and the abort controller gets
          // triggered, in which case we will not receive the finish event
          linkedCancellationSource.onCancellationRequested(() => {
            this.run.appendOutput("\r\nTest run cancelled.");
            abortController.abort();
            finalize();
          });

          this.disposables.push(
            connection.onNotification(NOTIFICATION_TYPES.finish, finalize),
          );

          this.registerStreamingEvents(connection);

          // Start listening for events
          connection.listen();
        });

        if (mode === Mode.Run) {
          this.spawnTestProcess(
            command,
            env,
            workspace.workspaceFolder.uri.fsPath,
            serverPort,
            abortController,
          );
        } else {
          await this.launchDebugger(command, env, workspace, serverPort);
        }
      });
    });
  }

  // Launches the debugger with streaming updates
  private async launchDebugger(
    command: string,
    env: NodeJS.ProcessEnv,
    workspace: Workspace,
    serverPort: string,
  ) {
    await vscode.debug
      .startDebugging(
        workspace.workspaceFolder,
        {
          type: "ruby_lsp",
          name: "Debug",
          request: "launch",
          program: command,
          env: {
            ...env,
            DISABLE_SPRING: "1",
            RUBY_LSP_REPORTER_PORT: serverPort,
          },
        },
        { testRun: this.run },
      )
      .then((successFullyStarted) => {
        if (!successFullyStarted) {
          throw new Error("Failed to start debugging session");
        }
      });
  }

  // Spawns the test process and redirects any stdout or stderr output to the test run output
  private spawnTestProcess(
    command: string,
    env: NodeJS.ProcessEnv,
    cwd: string,
    serverPort: string,
    abortController: AbortController,
  ) {
    const testProcess = spawn(command, {
      env: { ...env, RUBY_LSP_REPORTER_PORT: serverPort },
      stdio: ["pipe", "pipe", "pipe"],
      shell: true,
      signal: abortController.signal,
      cwd,
    });

    testProcess.stdout.on("data", (data) => {
      this.run.appendOutput(data.toString().replace(/\n/g, "\r\n"));
    });

    testProcess.stderr.on("data", (data) => {
      this.run.appendOutput(data.toString().replace(/\n/g, "\r\n"));
    });
  }

  // Registers all streaming events that we will receive from the server except for the finish event, which is
  // registered to resolve the execute promise
  private registerStreamingEvents(connection: rpc.MessageConnection) {
    const startTimestamps = new Map<string, number>();
    const withDuration = (
      id: string,
      callback: (duration?: number) => void,
    ) => {
      const startTime = startTimestamps.get(id);
      const duration = startTime ? Date.now() - startTime : undefined;
      callback(duration);
    };

    // Handle the JSON events being emitted by the tests
    this.disposables.push(
      connection.onNotification(NOTIFICATION_TYPES.start, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                this.run.started(test);
                startTimestamps.set(test.id, Date.now());
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      connection.onNotification(NOTIFICATION_TYPES.pass, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run.passed(test, duration),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      connection.onNotification(NOTIFICATION_TYPES.fail, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run.failed(
                    test,
                    new vscode.TestMessage(params.message),
                    duration,
                  ),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      connection.onNotification(NOTIFICATION_TYPES.error, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                withDuration(test.id, (duration) =>
                  this.run.errored(
                    test,
                    new vscode.TestMessage(params.message),
                    duration,
                  ),
                );
              }
            },
          ),
        );
      }),
    );

    this.disposables.push(
      connection.onNotification(NOTIFICATION_TYPES.skip, (params) => {
        this.promises.push(
          this.findTestItem(params.id, vscode.Uri.parse(params.uri)).then(
            (test) => {
              if (test) {
                this.run.skipped(test);
              }
            },
          ),
        );
      }),
    );
  }
}
