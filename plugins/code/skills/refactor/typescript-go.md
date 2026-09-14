# TypeScript and Go refactoring

Use the relevant language section while reading an implementation or reviewing a proposed
change. These are questions about behavior and ownership, not a mandatory architecture
or a reason to add tools. The repository's supported runtime and checks take precedence.

## TypeScript

- Establish the workspace/package boundaries from manifests, lockfiles, exports, and
  `tsconfig` files. Resolve aliases and re-exports before calling an import unused.
  Separate type-only dependencies from runtime imports, side-effect registration, and
  dynamic loading. Moving a file can alter module initialization or create a runtime cycle.
- Follow the existing source of truth for data shapes: schema, generated client, or domain
  type. Derive a compatible view when appropriate; do not maintain another hand-copied
  interface. Keep a distinct type when it expresses a real boundary, such as a public
  response that excludes private storage fields. Static types do not validate HTTP input.
- Inspect routing and middleware composition before calling router-to-handler delegation
  duplicate code. Preserve validation, authorization order, status/error shapes, streaming,
  and cancellation through the refactor. Collapsing wrappers is useful when it removes a
  repeated decision without losing a boundary's behavior.
- Prefer the existing module and ordinary functions when they express the responsibility.
  A generic repository, provider hierarchy, or barrel of re-exports must solve a demonstrated
  caller problem; fewer source lines alone do not justify the extra indirection.
- Use the package's pinned compiler and canonical typecheck, lint, and test commands.
  Check [project references](https://www.typescriptlang.org/docs/handbook/project-references.html)
  when choosing the scope: a root invocation may not cover every package. Passing a
  transpiler/build is not evidence that types or runtime contracts were checked.

## Go

- Discover `go.mod`, any `go.work`, module replacements, build tags, and generated sources.
  Resolve imports to packages, not individual files. Splitting a large file within its
  package can improve readability without creating another exported API or `go.mod`.
  Extract a package only when its ownership and import direction justify that boundary.
- Read receivers and call sites before merging methods with similar signatures. Keep
  domain types distinct when they enforce different operations or wire contracts; do not
  turn them into aliases just to lower the type count. Define small consumer interfaces
  for actual substitution needs, not one interface per struct or solely to permit mocking.
- Preserve context cancellation, error identity/wrapping, zero-value behavior, and JSON
  tags/omission rules. For concurrent or I/O code, identify who closes bodies/channels,
  releases locks, and ends goroutines; moving ownership can change behavior despite
  identical function signatures.
- Use the canonical build/test scripts with their required tags and generation steps.
  Discover the actual module coverage before using `go test ./...` or `go vet ./...`;
  do not claim a workspace-root invocation checked nested modules. Use the configured
  analyzer (such as Staticcheck or golangci-lint) if present, and a supported race-enabled
  run when changing shared state or goroutine lifetimes. The
  [race detector](https://go.dev/doc/articles/race_detector) checks executed paths;
  a pass does not prove unexercised paths race-free.

## Replacing custom code with a library

Check the standard library and already-installed framework/SDK before proposing a new
dependency or extracting a private library. Inspect the exact custom behavior and the
candidate's current API/version: authentication, retries, pagination, streaming, errors,
and cancellation often contain the code that must remain. Show a small replacement at
the existing call site, what custom code disappears, what adapter remains, and the net
maintenance cost. A package with a matching name is not proof it fits. Preserve required
runtime, license, security, and deployment constraints; verify against primary docs and a
representative execution before claiming equivalence. Avoid unrelated dependency upgrades.

## Tests that survive consolidation

Map changed behavior to its existing caller-level checks. Keep tests that catch distinct
failures; consolidate repetitive cases without removing coverage simply to meet a line
budget. Examine what the test executes: mocking the module being refactored cannot prove
its real behavior. Exercise the actual implementation and use the repository's integration
or canary path for external contracts. Report a missing dependency or unrun check plainly.
For API changes, an unchanged route inventory proves only the surface it records; compare
the affected validation, authorization, response, and failure behavior as well.
