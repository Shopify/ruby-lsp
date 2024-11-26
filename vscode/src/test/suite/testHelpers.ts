import { EventEmitter, Readable, Writable } from "stream";
import { SpawnOptions } from "child_process";

import sinon from "sinon";

import * as common from "../../common";

interface SpawnStubOptions {
  stdout?: string;
  stderr?: string;
  exitCode?: number;
}

export function createSpawnStub({
  stdout = "",
  stderr = "",
  exitCode = 0,
}: SpawnStubOptions = {}): { spawnStub: sinon.SinonStub; stdinData: string[] } {
  const stdinData: string[] = [];

  const spawnStub = sinon
    .stub(common, "spawn")
    .callsFake(
      (
        _command: string,
        _args: ReadonlyArray<string>,
        _options: SpawnOptions,
      ) => {
        const childProcess = new EventEmitter() as any;

        childProcess.stdout = new Readable({
          read() {},
        });
        childProcess.stderr = new Readable({
          read() {},
        });
        childProcess.stdin = new Writable({
          write(chunk, _encoding, callback) {
            stdinData.push(chunk.toString());
            callback();
          },
          final(callback) {
            process.nextTick(() => {
              childProcess.stdout.emit("data", stdout);
              childProcess.stderr.emit("data", stderr);

              childProcess.emit("close", exitCode);
            });

            callback();
          },
        });

        return childProcess;
      },
    );

  return { spawnStub, stdinData };
}
