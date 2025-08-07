const path = require("path");
const os = require("os");
const net = require("net");

const port = process.env.RUBY_LSP_REPORTER_PORT ? process.env.RUBY_LSP_REPORTER_PORT : process.argv[2].trim();

const socket = new net.Socket();
socket.connect(parseInt(port, 10), "localhost", () => {

  const sendMessage = (message) => {
    const jsonMessage = JSON.stringify(message);
    socket.write(`Content-Length: ${jsonMessage.length}\r\n\r\n${jsonMessage}`);
  };

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

      sendMessage({ method: "finish", params: {} });

      setTimeout(() => { socket.end(); }, 1000);
    }, 1000);
  }, 1000);
});
