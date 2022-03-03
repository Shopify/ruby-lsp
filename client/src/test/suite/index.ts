import * as path from "path";

import * as Mocha from "mocha";
import * as glob from "glob";

export function run(): Promise<void> {
  // Create the mocha test
  const mocha = new Mocha({
    ui: "tdd",
    color: true,
  });

  const testsRoot = path.resolve(__dirname, "..");

  return new Promise((resolve, reject) => {
    glob("**/**.test.js", { cwd: testsRoot }, (globError, files) => {
      if (globError) {
        return reject(globError);
      }

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
    });
  });
}
