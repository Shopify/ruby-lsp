const path = require("path");
const os = require("os");

function sendMessage(message) {
  const jsonMessage = JSON.stringify(message);
  // eslint-disable-next-line no-console
  process.stdout.write(`Content-Length: ${jsonMessage.length}\r\n\r\n${jsonMessage}`);
}

const serverFilePath = path.join(__dirname, "..", "..", "..", "..", "test", "server_test.rb");
const uri = os.platform() === "win32" ? `file:///${serverFilePath.replace(/\\/g, '/')}` : `file://${serverFilePath}`;

setTimeout(() => {
  sendMessage({
    method: "start",
    params: { id: "ServerTest::NestedTest#test_something", uri: uri },
  });
}, 1000);

setTimeout(() => {
  setTimeout(() => {
    sendMessage({
      method: "pass",
      params: { id: "ServerTest::NestedTest#test_something", uri: uri },
    });

    setTimeout(() => {}, 1000);
  }, 1000);
}, 1000);
