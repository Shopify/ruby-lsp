import * as vscode from "vscode";

export class LinkedCancellationSource implements vscode.Disposable {
  private readonly tokenSource = new vscode.CancellationTokenSource();

  constructor(token: vscode.CancellationToken, ...additionalTokens: vscode.CancellationToken[]) {
    [token, ...additionalTokens].forEach((token) => {
      token.onCancellationRequested(() => {
        this.tokenSource.cancel();
      });
    });
  }

  dispose() {
    this.tokenSource.dispose();
  }

  isCancellationRequested() {
    return this.tokenSource.token.isCancellationRequested;
  }

  onCancellationRequested(callback: () => void | Promise<void>) {
    this.tokenSource.token.onCancellationRequested(callback);
  }
}
