import * as vscode from "vscode";

export class LinkedCancellationSource implements vscode.Disposable {
  private readonly tokenSource = new vscode.CancellationTokenSource();
  private readonly disposables: vscode.Disposable[] = [this.tokenSource];

  constructor(
    token: vscode.CancellationToken,
    ...additionalTokens: vscode.CancellationToken[]
  ) {
    [token, ...additionalTokens].forEach((token) => {
      const disposable = token.onCancellationRequested(() => {
        this.tokenSource.cancel();
      });

      this.disposables.push(disposable);
    });
  }

  dispose() {
    this.disposables.forEach((disposable) => disposable.dispose());
  }

  isCancellationRequested() {
    return this.tokenSource.token.isCancellationRequested;
  }

  onCancellationRequested(callback: () => void) {
    this.disposables.push(
      this.tokenSource.token.onCancellationRequested(callback),
    );
  }
}
