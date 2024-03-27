/* eslint-disable no-process-env */
import assert from "assert";
import path from "path";
import os from "os";

import * as vscode from "vscode";
import sinon from "sinon";

import { Rvm } from "../../../ruby/rvm";
import { WorkspaceChannel } from "../../../workspaceChannel";
import * as common from "../../../common";

suite("RVM", () => {
  if (os.platform() === "win32") {
    // eslint-disable-next-line no-console
    console.log("Skipping RVM tests on Windows");
    return;
  }

  test("Populates the gem env and path", async () => {
    const workspacePath = process.env.PWD!;
    const workspaceFolder = {
      uri: vscode.Uri.from({ scheme: "file", path: workspacePath }),
      name: path.basename(workspacePath),
      index: 0,
    };
    const outputChannel = new WorkspaceChannel("fake", common.LOG_CHANNEL);
    const rvm = new Rvm(workspaceFolder, outputChannel);

    const activationScript = [
      "STDERR.print(",
      "{yjit:!!defined?(RubyVM::YJIT),version:RUBY_VERSION,",
      "home:Gem.user_dir,default:Gem.default_dir,ruby:RbConfig.ruby}",
      ".to_json)",
    ].join("");

    const execStub = sinon.stub(common, "asyncExec").resolves({
      stdout: "",
      stderr: JSON.stringify({
        yjit: true,
        version: "3.0.0",
        home: "/home/user/.rvm/gems/ruby/3.0.0",
        default: "/usr/lib/ruby/gems/3.0.0",
        ruby: "/home/user/.rvm/rubies/ruby-3.0.0/bin/ruby",
      }),
    });

    const { env, version, yjit } = await rvm.activate();

    assert.ok(
      execStub.calledOnceWithExactly(
        `${path.join(os.homedir(), ".rvm", "bin", "rvm-auto-ruby")} -W0 -rjson -e '${activationScript}'`,
        { cwd: workspacePath },
      ),
    );

    assert.strictEqual(version, "3.0.0");
    assert.strictEqual(yjit, true);
    assert.strictEqual(env.GEM_HOME, "/home/user/.rvm/gems/ruby/3.0.0");
    assert.strictEqual(
      env.GEM_PATH,
      "/home/user/.rvm/gems/ruby/3.0.0:/usr/lib/ruby/gems/3.0.0",
    );
    assert.ok(env.PATH!.includes("/home/user/.rvm/gems/ruby/3.0.0/bin"));
    assert.ok(env.PATH!.includes("/usr/lib/ruby/gems/3.0.0/bin"));
    assert.ok(env.PATH!.includes("/home/user/.rvm/rubies/ruby-3.0.0/bin"));

    execStub.restore();
  });
});
