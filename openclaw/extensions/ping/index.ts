export default function (api) {
  api.registerCommand({
    name: "ping",
    description: "Test that the plugin is loaded",
    handler: () => ({ text: "pong!" }),
  });
}
