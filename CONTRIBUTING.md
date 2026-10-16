# Contributing

Thanks for helping! The most valuable contributions are **new or corrected rules**: every rule makes the scanner more useful for every admin who runs it.

- Found a missing or wrong rule but don't want to write code? [Open a rule issue](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new?template=new-rule.yml). A link to the official source is all we need.
- Found a bug? [Open a bug report](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new?template=bug-report.yml) with a minimal script.
- Security problem? Do not open a public issue. See [SECURITY.md](SECURITY.md).

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

You need PowerShell 7 for the build script. The module itself also runs on Windows PowerShell 5.1.

1. Clone the repository:

   ```powershell
   git clone https://github.com/matejpaunovski/M365DeprecationScanner.git
   ```

2. Install the tools (Pester 5 and PSScriptAnalyzer, for the current user):

   ```powershell
   ./build.ps1 -Task Bootstrap
   ```

3. Run everything CI runs (analyze, docs check, tests):

   ```powershell
   ./build.ps1
   ```

Single tasks:

| Command | What it does |
|---|---|
| `./build.ps1 -Task Test` | Run all Pester tests |
| `./build.ps1 -Task Analyze` | Run PSScriptAnalyzer on module, action, build script and tools |
| `./build.ps1 -Task Docs` | Regenerate `docs/rules.md` from the rule database |
| `./build.ps1 -Task All` | All of the above, with a check that `docs/rules.md` is up to date (default) |

Try your change interactively:

```powershell
Import-Module ./src/M365DeprecationScanner -Force
```

```powershell
Invoke-M365DeprecationScan -Path ./examples/legacy-script.ps1
```

## Repository layout

```text
src/M365DeprecationScanner/
  M365DeprecationScanner.psd1        module manifest (version lives here)
  M365DeprecationScanner.psm1        loads Private/ and Public/
  M365DeprecationScanner.Format.ps1xml  default table views
  Public/                            exported commands, one file per function
  Private/                           engine, suppression, reports
  Rules/M365DeprecationScanner.Rules.psm1  PSScriptAnalyzer custom rule
  Data/deprecations.json             the rule database
  Data/deprecations.schema.json      JSON schema for rule files
action.yml, action/Invoke-Action.ps1 GitHub Action
tests/                               Pester 5 tests (+ Fixtures/test-rules.json)
tools/New-RuleCatalog.ps1            generates docs/rules.md
examples/                            legacy-script.ps1 (must have findings), modern-script.ps1 (must be clean)
docs/                                user documentation
build.ps1                            build, test and docs tasks
```

How the engine works: [docs/how-it-works.md](docs/how-it-works.md).

## Adding or changing a rule

All rules live in `src/M365DeprecationScanner/Data/deprecations.json`. The field reference and examples for every rule kind are in [docs/custom-rules.md](docs/custom-rules.md). The built-in database follows the same format, with a few extra rules:

1. **An official source is required.** Link Microsoft Learn, the Microsoft Tech Community blog or a Microsoft 365 message center post in `sources`. Blog posts or forum threads by third parties are not enough on their own.
2. **Never renumber or reuse an id.** Users reference ids in suppression comments and pipeline settings. If a rule is wrong, fix it. If it must go, delete it and leave the number unused.
3. **Use the prefix of the area** and the next free number:

   | Area | Prefix |
   |---|---|
   | `MSOnline` | `MSOL` |
   | `AzureAD` | `AAD` |
   | `ExchangeOnline` | `EXO` |
   | `MicrosoftGraph` | `MGSDK` |
   | `AzureADGraph` | `AADG` |
   | `Azure` | `AZ` |
   | `Teams` | `TEAMS` |
   | `SharePoint` | `SPO` |
   | `Other` | `OTHER` |

   `Intune` has no rules yet. Propose a prefix in your pull request (for example `INTUNE`).
4. **Exact rules plus one catch-all.** Add an exact `Command` rule for each important command with its specific replacement. Keep one wildcard catch-all per retired module (for example `*-Msol*`) for everything else. Exact rules always win over the catch-all, so adding exact rules never causes double findings.
5. **Write a short title that ends with a period.** One sentence, at most 160 characters. Put migration details (parameter changes, permission scopes, different output objects) in `notes`.
6. **Pick the right status.** `Retired` = no longer works. `Deprecated` = still works, but support has ended or retirement is announced. `Announced` = retirement announced for a future date. Add `retirementDate` when Microsoft names one.
7. **Keep `examples/modern-script.ps1` clean.** If your rule flags modern code, the pattern is too broad.
8. **Regenerate the catalog:**

   ```powershell
   ./build.ps1 -Task Docs
   ```

   Never edit `docs/rules.md` by hand. CI fails if it is out of date.
9. **Add a CHANGELOG entry** under `## [Unreleased]` in a `### Rules` section, for example:

   ```markdown
   ### Rules

   - Added EXO0018: `Get-Foo` is retired, use `Get-Bar`.
   ```

10. Run `./build.ps1`. `tests/Database.Tests.ps1` checks the schema, unique ids, title format, sources and patterns for every rule.

Also update `lastUpdated` at the top of the database file.

## Code style

- **Windows PowerShell 5.1 compatible syntax** in everything under `src/`. No ternary operator, no `??` / `?.`, no `&&` / `||` pipeline chains. PSScriptAnalyzer checks this (`PSUseCompatibleSyntax` for 5.1 and 7.4).
- `build.ps1`, `tools/` and `action/` may use PowerShell 7.
- **Comment-based help** on every public function: synopsis, description, every parameter and at least one example. `tests/Module.Tests.ps1` enforces this.
- One public function per file in `Public/`. The file name is the function name.
- 4 spaces indentation (2 for JSON and YAML), UTF-8. See `.editorconfig`. `deprecations.json` must be UTF-8 without BOM (a test checks this).
- Tests use **Pester 5**. Add a test for every bug fix and every engine change. Use `tests/Fixtures/test-rules.json` for engine tests so they don't depend on the real database.
- PSScriptAnalyzer must report no issues (`./build.ps1 -Task Analyze`).

## Pull requests

1. Fork, create a branch, make your change.
2. Run `./build.ps1`.
3. Open a pull request and fill in the checklist from the [pull request template](.github/pull_request_template.md).

Keep pull requests focused. Several new rules in one PR are fine. Rules and engine changes are better in separate PRs.

## Release process (maintainers)

1. Bump `ModuleVersion` in `src/M365DeprecationScanner/M365DeprecationScanner.psd1` ([Semantic Versioning](https://semver.org/)).
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a new empty `## [Unreleased]` above it and update the compare links at the bottom. `tests/Module.Tests.ps1` checks that the current version has an entry.
3. Commit and merge to `main`.
4. Tag and push:

   ```bash
   git tag vX.Y.Z
   ```

   ```bash
   git push origin vX.Y.Z
   ```

5. The [release workflow](.github/workflows/release.yml) checks that the tag matches `ModuleVersion`, runs all tests, publishes to the PowerShell Gallery and creates a GitHub release.
6. Move the major tag used by the Action (for example `v0`) to the new release:

   ```bash
   git tag -f v0 vX.Y.Z
   ```

   ```bash
   git push -f origin v0
   ```

One-time setup for the release workflow:

- A repository secret `PSGALLERY_API_KEY` with a PowerShell Gallery API key ([create one here](https://www.powershellgallery.com/account/apikeys)).
- A GitHub environment named `release`. Add required reviewers there if releases should need approval.
