import fs from "fs";
import path from "path";

export const RUBY_VERSION = fs
  .readFileSync(
    path.join(
      path.dirname(path.dirname(path.dirname(__dirname))),
      ".ruby-version",
    ),
    "utf-8",
  )
  .trim();
