import * as net from 'net';

/** One private server session. Callers serialize requests; cancellation destroys it. */
export class RuntimeConnection {
  private readonly socket: net.Socket;
  private buffer = Buffer.alloc(0);
  private ready = false;
  private failure?: Error;
  private receive?: (kind: number, payload: Buffer) => void;
  private reject?: (error: Error) => void;
  private begin?: () => void;

  constructor(socketPath: string, private readonly onClose?: () => void) {
    this.socket = net.createConnection(socketPath);
    this.socket.on('error', error => this.close(error));
    this.socket.on('end', () => this.close(Object.assign(new Error('RecurLoop server closed the session'), { code: this.ready ? undefined : 'ECONNRESET' })));
    this.socket.on('data', chunk => {
      this.buffer = Buffer.concat([this.buffer, chunk]);
      if (!this.ready) {
        if (this.buffer.length < 2) return;
        if (this.buffer.subarray(0, 2).toString() !== '> ') { this.close(new Error('Invalid RecurLoop server greeting')); return; }
        this.ready = true;
        this.buffer = this.buffer.subarray(2);
        this.socket.write(':transport-stream-v2\n');
        this.begin?.();
      }
      while (this.buffer.length >= 5) {
        const kind = this.buffer[0];
        const length = this.buffer.readUInt32BE(1);
        if (length > 4096) { this.close(new Error('Invalid RecurLoop response frame')); return; }
        if (this.buffer.length < 5 + length) return;
        const payload = this.buffer.subarray(5, 5 + length);
        this.buffer = this.buffer.subarray(5 + length);
        this.receive?.(kind, payload);
      }
    });
  }

  request(commands: string[], timeoutMs?: number, signal?: AbortSignal): Promise<string> {
    if (signal?.aborted) return Promise.reject(signal.reason);
    if (this.failure) return Promise.reject(this.failure);
    if (this.receive) return Promise.reject(new Error('Concurrent request on a private RecurLoop session'));
    return new Promise((resolve, reject) => {
      let command = 0;
      let status: number | undefined;
      let chunks: Buffer[] = [];
      const replies: string[] = [];
      const abort = () => this.close(signal!.reason);
      const timer = timeoutMs === undefined ? undefined : setTimeout(() =>
        this.close(new Error(`RecurLoop analysis request timed out after ${timeoutMs} ms`)), timeoutMs);
      const finish = (error?: Error) => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', abort);
        this.receive = undefined; this.reject = undefined; this.begin = undefined;
        if (error) reject(error); else resolve(replies.join(''));
      };
      const send = () => {
        if (command < commands.length) this.socket.write(commands[command++] + '\n');
        else finish();
      };
      this.reject = finish;
      this.begin = send;
      this.receive = (kind, payload) => {
        if (kind === 79) chunks.push(payload);
        else if (kind === 83 && /^-?\d+$/.test(payload.toString('ascii'))) status = Number(payload.toString('ascii'));
        else if (kind === 80 && !payload.length && status !== undefined) {
          const reply = Buffer.concat(chunks).toString('utf8');
          if (status !== 0) { this.close(new Error(`${reply}\nstatus=${status}`)); return; }
          replies.push(reply); chunks = []; status = undefined; send();
        } else this.close(new Error('Invalid RecurLoop response frame'));
      };
      signal?.addEventListener('abort', abort, { once: true });
      if (this.ready) send();
    });
  }

  close(error = new Error('RecurLoop session disposed')): void {
    if (this.failure) return;
    this.failure = error;
    this.socket.destroy();
    this.onClose?.();
    this.reject?.(error);
  }
}
