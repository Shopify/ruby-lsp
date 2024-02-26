import * as path from "path";

import Mocha from "mocha";
import { glob } from "glob";

export function run(): Promise<void> {
  // Create the mocha test
  const mocha = new Mocha({
    ui: "tdd",
    color: true,
  });

  const testsRoot = path.resolve(__dirname, "..");

  return new Promise((resolve, reject) => {
    glob("**/**.test.js", { cwd: testsRoot })
      .then((files: string[]) => {
        // Add files to the test suite
        files.forEach((file) => mocha.addFile(path.resolve(testsRoot, file)));

        try {
          // Run the mocha test
          mocha.run((failures) => {
            if (failures > 0) {
              reject(new Error(`${failures} tests failed.`));
            } else {
              resolve();
            }
          });
        } catch (err) {
          // eslint-disable-next-line no-console
          console.error(err);
          reject(err);
        }
      })
      .catch((globError) => {
        if (globError) {
          return reject(globError);
        }
      });
  });
}
