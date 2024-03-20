import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rbenv } from "../../../ruby/rbenv";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

suite("Rbenv", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping Rbenv tests on Windows");
    return;
  }

  test("Finds Ruby based on .ruby-version", async () => {
    // eslint-disable-next-line no-process-env
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rbenv = new Rbenv(workspaceFolder, outputChannel);

    const activationScript = [
      "STDERR.print(",
      "{env: ENV.to_h,yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION,home:Gem.user_dir,default:Gem.default_dir}",
      ".to_json)",
    ].join("");

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        env: { ANY: "true" },
        yjit: true,
        version: "3.0.0",
        home: "/home/user/.gem/ruby/3.0.0",
        default: "/usr/lib/ruby/gems/3.0.0",
      }),
    });

    const { env, version, yjit } = await rbenv.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `rbenv exec ruby -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.GEM_HOME, "/home/user/.gem/ruby/3.0.0");
    assert.strictEqual(
      env.GEM_PATH,
      "/home/user/.gem/ruby/3.0.0:/usr/lib/ruby/gems/3.0.0",
    );
    assert.ok(env.PATH!.includes("/home/user/.gem/ruby/3.0.0/bin"));
    assert.ok(env.PATH!.includes("/usr/lib/ruby/gems/3.0.0/bin"));
    assert.strictEqual(env.ANY, "true");

    execStub.restore();
  });
});
