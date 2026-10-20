import * as path from 'path';
import * as vscode from 'vscode';

export type ReportProgress = (message: string) => void;
export type RuntimeProgress = <T>(uri: vscode.Uri, title: string,
  task: (report: ReportProgress) => Promise<T>) => Promise<T>;

/** Each workspace operation owns a clickable status item until it settles. */
export function runtimeProgress(output: vscode.OutputChannel): RuntimeProgress {
  return async (uri, title, task) => {
    const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 0);
    status.name = `RecurLoop: ${path.basename(uri.fsPath)}`;
    status.command = 'recurloop.showProcessingLog';
    const display = (message: string) => {
      status.text = `$(sync~spin) RecurLoop: ${message.length > 100 ? message.slice(0, 97) + '…' : message}`;
      status.tooltip = `${title}\n${uri.fsPath}\n${message}\nClick to open the processing log.`;
    };
    display(title);
    status.show();
    const started = Date.now();
    const log = (message: string) => output.appendLine(`[${new Date().toISOString()}] [${uri.fsPath}] ${message}`);
    log(title);
    try {
      const result = await task(message => { display(message); log(message); });
      log(`${title}: ready (${((Date.now() - started) / 1000).toFixed(1)} s)`);
      return result;
    } catch (error) {
      log(`${title}: failed: ${error}`);
      throw error;
    } finally {
      status.dispose();
    }
  };
}
