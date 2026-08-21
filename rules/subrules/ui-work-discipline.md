# UI Work — See It Before "Done", Design It for the Eyes

## Verify UI by looking at it

- A UI or visual change is not verified until you have seen the rendered result and judged it against the intent. A passing build or present bundle strings are proxies, not proof (F3).
- **One-off HTML and worker-host UI:** render headlessly with a bare `agents browser start --url file://<absolute-path>`, capture it with `agents browser screenshot -o .agents/scratch/<name>.png`, then read that exact path with `view_image` and critique it. On workers, never pass `--profile` or hunt for a browser binary; the machine resolves its configured headless profile.
- **Webview or web UI:** first check for the repository's preview harness (Vite, Storybook, or a `/preview` route), then use `agents browser` against that real surface and inspect a screenshot.
- **Native UI:** use `agents computer` in element mode. `describe` returns element refs; `click --id` and `type --id` do not steal foreground focus. Never use `--raise` or coordinate clicks on a machine the user is using. Screenshots are focus-safe.
- Render and inspect on the machine doing the work. Transfer or `open` the result on the interactive host only when the user explicitly requested it, and never before read-back.

## Design for what the user will see

- Lead with the visible behavior and appearance, then the implementation details.
- Product mockups must use the product's real layout, components, and visual language. Abstract diagrams do not substitute for a product-faithful mockup.
- When a genuine design choice exists, show two or three rendered variations with one-line tradeoffs and stop for the user's choice.
