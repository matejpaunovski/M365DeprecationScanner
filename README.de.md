# M365 Deprecation Scanner

> English version: [README.md](README.md)

**Findet in deinen PowerShell-Skripten alles, was Microsoft schon abgeschaltet hat oder bald abschaltet, und sagt dir, was du stattdessen nimmst.**

## Warum?

Microsoft stellt laufend Module und Cmdlets ein: **MSOnline** und **AzureAD** sind weg, **Remote PowerShell** für Exchange Online ist abgeschaltet, `Get-MessageTrace` wird ersetzt, die **Azure AD Graph API** ist eingestellt, **AzureRM** ist Geschichte.

Alte Skripte merken davon nichts, bis sie laufen. Dann scheitert der geplante Task um 3 Uhr nachts, oder schlimmer: Er läuft durch und tut nichts. In vielen Firmen liegen Dutzende solcher Skripte auf Fileshares, in Aufgabenplanungen und in Azure Automation. Niemand weiß, welche davon schon kaputt sind.

Der M365 Deprecation Scanner beantwortet das in Sekunden.

## So benutzt du es

### Schritt 1: Modul installieren

PowerShell öffnen (Adminrechte sind nicht nötig) und ausführen:

```powershell
Install-Module -Name M365DeprecationScanner -Scope CurrentUser
```

Funktioniert mit Windows PowerShell 5.1 und PowerShell 7. Ab PowerShell 7.4 geht auch `Install-PSResource -Name M365DeprecationScanner`.
Du brauchst weder MSOnline noch AzureAD oder ein anderes Microsoft-Modul und auch keine Verbindung zu deinem Tenant.

### Schritt 2: Skripte scannen

Nimm die Zeile, die zu dem passt, was du scannen willst:

| Befehl | Was passiert |
|---|---|
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse` | **Scannt den ganzen Ordner inklusive aller Unterordner.** Das willst du meistens. |
| `Invoke-M365DeprecationScan -Path C:\Scripts` | Scannt nur die Dateien direkt in `C:\Scripts`, **nicht** die Unterordner. |
| `Invoke-M365DeprecationScan -Path . -Recurse` | Scannt den Ordner, in dem du gerade bist (vorher mit `cd` hinwechseln), inklusive Unterordner. |
| `Invoke-M365DeprecationScan -Path .\Get-Licenses.ps1` | Scannt eine einzelne Datei. |
| `Invoke-M365DeprecationScan -Path C:\Scripts, D:\Automation -Recurse` | Scannt mehrere Ordner auf einmal. |
| `Invoke-M365DeprecationScan -ScriptDefinition 'Get-MsolUser -All'` | Prüft ein Code-Schnipsel, ohne es als Datei zu speichern. |

In Ordnern werden `.ps1`-, `.psm1`- und `.psd1`-Dateien gesucht. Deine Skripte werden nur gelesen, nie ausgeführt.

### Schritt 3: Ergebnis lesen

Jede Zeile im Ergebnis ist eine Stelle in deinem Code, die du dir ansehen solltest:

- **File / Line**: wo die Stelle ist.
- **Severity**: `Error` = funktioniert nicht mehr, jetzt fixen. `Warning` = läuft noch, ist aber veraltet, bald fixen. `Information` = Abschaltung angekündigt, einplanen.
- **Found**: der alte Befehl, Parameter, das Modul oder die URL.
- **Use instead**: was du stattdessen nimmst.

Wird nichts gefunden, sagt der Scanner das: `No deprecated or retired commands found in 12 file(s).`

### Schritt 4: Mehr Details (optional)

| Befehl | Was passiert |
|---|---|
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse \| Format-List` | Zeigt alle Details pro Fund: Migrationshinweise, Abschaltdatum und die offizielle Microsoft-Quelle. |
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -MinimumSeverity Error` | Zeigt nur, was schon kaputt ist. |
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -Exclude '*\archiv\*'` | Lässt Ordner oder Dateien aus, die dich nicht interessieren. |
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse \| Export-M365DeprecationReport -Format Html -Path .\report.html` | Erstellt einen HTML-Report für den Browser oder zum Weiterschicken ans Team. |
| `Invoke-M365DeprecationScan -Path C:\Scripts -Recurse \| Export-M365DeprecationReport -Format Csv -Path .\report.csv` | Erstellt eine CSV-Datei für Excel. |
| `Get-M365DeprecationRule -Name Get-MsolUser \| Format-List` | Schlägt einen einzelnen Befehl nach: was ihn ersetzt und warum. |
| `Get-Help Invoke-M365DeprecationScan -Full` | Zeigt die komplette eingebaute Hilfe mit allen Parametern und Beispielen. |

### Schritt 5: Fixen und nochmal scannen

Ersetze die alten Befehle nacheinander (die Spalte **Use instead** und die verlinkte Microsoft-Doku sagen dir wie) und lass denselben Scan danach nochmal laufen, bis nichts mehr gefunden wird.

Für neue Regeln später einfach das Modul aktualisieren: `Update-Module M365DeprecationScanner`.

Mehr dazu: [Getting started](docs/getting-started.md) (Englisch).

## Was es findet

| Bereich | Beispiele (alt → neu) |
|---|---|
| **MSOnline** | `Connect-MsolService` → `Connect-MgGraph`, `Get-MsolUser` → `Get-MgUser` |
| **AzureAD / AzureADPreview** | `Connect-AzureAD` → `Connect-MgGraph`, `Get-AzureADGroupMember` → `Get-MgGroupMember` |
| **Exchange Online** | `Connect-ExchangeOnline -UseRPSSession` → ohne `-UseRPSSession`, `Get-MessageTrace` → `Get-MessageTraceV2`, `Search-AdminAuditLog` → `Search-UnifiedAuditLog` |
| **Azure AD Graph** | `https://graph.windows.net/...` → `https://graph.microsoft.com/...` |
| **AzureRM** | `Login-AzureRmAccount` → `Connect-AzAccount`, `Get-AzureRm*` → `Get-Az*` |
| **Microsoft Graph SDK v1** | `Select-MgProfile` → Modul `Microsoft.Graph.Beta` |
| **Teams, SharePoint** | `SkypeOnlineConnector` → `MicrosoftTeams`, `SharePointPnPPowerShellOnline` → `PnP.PowerShell` |

Der Scanner versteht PowerShell, er macht kein einfaches Textsuchen. Er erkennt:

- **Befehle**, auch mit Modulpräfix (`MSOnline\Get-MsolUser`) und in Funktionen oder Pipelines
- **Parameter** an bestimmten Befehlen (`Connect-ExchangeOnline -UseRPSSession`)
- **Module** in `Import-Module`, `Install-Module`, `#Requires -Modules`, `using module` und in Modul-Manifesten (`RequiredModules` / `NestedModules` in `.psd1`-Dateien)
- **Endpunkte** in Strings (`'https://graph.windows.net/...'`)

Kommentare werden ignoriert. Alle Regeln findest du im [Regelkatalog](docs/rules.md).

## Beispielausgabe

So sieht ein Scan von [`examples/legacy-script.ps1`](examples/legacy-script.ps1) aus (gekürzt):

```text
PS> Invoke-M365DeprecationScan -Path .\examples\legacy-script.ps1

File              Line Severity RuleId   Found                                 Use instead
----              ---- -------- ------   -----                                 -----------
legacy-script.ps1    9 Error    MSOL0001 #Requires -Modules MSOnline           Microsoft Graph PowerShell SDK (or Microsoft Entra PowerShell)
legacy-script.ps1   15 Error    MSOL0002 Connect-MsolService                   Connect-MgGraph
legacy-script.ps1   16 Error    AAD0003  Connect-AzureAD                       Connect-MgGraph
legacy-script.ps1   17 Error    EXO0002  Connect-ExchangeOnline -UseRPSSession Connect-ExchangeOnline (without -UseRPSSession)
legacy-script.ps1   20 Error    MSOL0003 Get-MsolUser                          Get-MgUser
legacy-script.ps1   28 Error    AAD0032  Get-AzureADGroupMember                Get-MgGroupMember
legacy-script.ps1   32 Warning  EXO0005  Get-MessageTrace                      Get-MessageTraceV2
legacy-script.ps1   36 Warning  AZ0004   Login-AzureRmAccount                  Connect-AzAccount
legacy-script.ps1   41 Error    AADG0001 graph.windows.net                     Microsoft Graph (https://graph.microsoft.com)
```

Die Severity ergibt sich aus dem Status der Regel:

| Severity | Status | Bedeutung |
|---|---|---|
| **Error** | Retired | Funktioniert nicht mehr. Jetzt fixen. |
| **Warning** | Deprecated | Läuft noch, aber der Support ist vorbei oder die Abschaltung angekündigt. Bald fixen. |
| **Information** | Announced | Abschaltung für ein späteres Datum angekündigt. Einplanen. |

## Drei Wege, den Scanner zu nutzen

### 1. Als PowerShell-Befehl

Nur das anzeigen, was schon kaputt ist:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -MinimumSeverity Error
```

Weitere Filter: `-Area`, `-ExcludeRuleId`, `-Include`, `-Exclude`. Siehe [Getting started](docs/getting-started.md#filtering).

### 2. In VS Code

Veraltete Befehle werden **beim Tippen** unterkringelt, der Ersatz steht im Tooltip. Settings-Datei anlegen:

```powershell
New-M365DeprecationAnalyzerSettings -Path "$HOME\PSScriptAnalyzerSettings.psd1"
```

Dann in VS Code die Einstellung `"powershell.scriptAnalysis.settingsPath"` auf diese Datei setzen. Nach einem Modul-Update den Befehl mit `-Force` neu ausführen, weil die Datei den Pfad der Modulversion enthält. Details: [docs/vscode.md](docs/vscode.md).

### 3. In der Pipeline (GitHub Action)

```yaml
- uses: actions/checkout@v5
- uses: matejpaunovski/M365DeprecationScanner@v0
  with:
    path: scripts
    fail-on: Error
```

Du bekommst Annotations im Code, eine Zusammenfassung auf der Job-Seite und optional eine SARIF-Datei für GitHub Code Scanning. Mit `fail-on: Error` schlägt der Build nur bei abgeschalteten Befehlen fehl. Details und ein Beispiel für Azure DevOps: [docs/github-action.md](docs/github-action.md).

## Reports

Leite die Ergebnisse an `Export-M365DeprecationReport` weiter:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse | Export-M365DeprecationReport -Format Html -Path .\deprecations.html
```

| Format | Wofür |
|---|---|
| `Html` | Eine Datei für Team oder Chef, mit Suche und Filter, funktioniert offline |
| `Markdown` | GitHub Job Summary, Pull-Request-Kommentare, Wikis |
| `Csv` | Excel |
| `Json` | Automatisierung |
| `Sarif` | GitHub Code Scanning und andere Security-Dashboards |

Details: [docs/reports.md](docs/reports.md).

## Funde unterdrücken

Manchmal ist eine Zeile absichtlich so, zum Beispiel in einem Migrationsskript. Dann unterdrückst du den Fund mit einem Kommentar:

```powershell
Connect-MsolService # m365ds-ignore: MSOL0002 - alter Tenant, wird in Q1 abgebaut
```

Außerdem gibt es `# m365ds-ignore-next-line` und `# m365ds-ignore-file`. Die Begründung gehört **hinter** die Regel-ID, getrennt mit einem Bindestrich. Direkt nach dem Doppelpunkt liest der Scanner das erste Wort als Regel-ID. Details: [docs/suppressions.md](docs/suppressions.md).

## Eigene Regeln

Ihr habt eine eigene Hilfsfunktion oder einen internen API-Endpunkt abgeschaltet? Leg eine eigene Regeldatei an, und der Scanner findet beides überall:

```powershell
Invoke-M365DeprecationScan -Path C:\Scripts -Recurse -CustomRulePath .\unsere-regeln.json
```

Aufbau der Datei und Beispiele: [docs/custom-rules.md](docs/custom-rules.md).

## Wie aktuell sind die Regeln?

- Jede Regel verlinkt eine **offizielle Microsoft-Quelle** (Microsoft Learn, Tech Community, Message Center). Die Links siehst du mit `Format-List`, im HTML-Report und im [Regelkatalog](docs/rules.md).
- Der Regelkatalog zeigt das Datum der letzten Aktualisierung.
- Die Regeln werden von der Community gepflegt. Fehlt etwas oder stimmt etwas nicht? [Issue aufmachen](https://github.com/matejpaunovski/M365DeprecationScanner/issues/new?template=new-rule.yml) oder einen Pull Request schicken, siehe [CONTRIBUTING.md](CONTRIBUTING.md#adding-or-changing-a-rule).

Prüf vor Änderungen an produktiven Skripten immer die verlinkte Quelle.

## FAQ

**Führt der Scanner meine Skripte aus?**
Nein. Die Skripte werden nur mit dem PowerShell-Parser gelesen. Nichts wird ausgeführt oder importiert.

**Braucht er Zugriff auf meinen Tenant oder das Internet?**
Nein. Alles läuft lokal gegen die Regeldatenbank, die mit dem Modul kommt.

**Läuft er unter Windows PowerShell 5.1?**
Ja. Windows PowerShell 5.1 und PowerShell 7 unter Windows, Linux und macOS. Die GitHub Action braucht PowerShell 7, das ist auf den GitHub-Runnern vorinstalliert.

**Kann er meine Skripte automatisch reparieren?**
Nein, und zwar mit Absicht. Die neuen Cmdlets haben oft andere Parameter, andere Berechtigungen und andere Ausgabeobjekte (zum Beispiel `Get-MsolUser` → `Get-MgUser`). Ein blindes Umbenennen erzeugt Code, der richtig aussieht und zur Laufzeit scheitert. Der Scanner zeigt dir, wo du hinschauen musst, und verlinkt die Migrationshinweise.

**Ersetzt er Tests?**
Nein. Er findet bekannte Abkündigungen. Ob dein Skript nach der Umstellung das Richtige tut, musst du weiterhin testen. Dynamischer Code wie `& $befehl` oder `Import-Module $name` lässt sich ohne Ausführung nicht auflösen und wird nicht erkannt.

## Mitmachen

Beiträge sind willkommen, vor allem **neue Regeln**. Jede Regel hilft allen, die den Scanner nutzen.

```powershell
./build.ps1 -Task Bootstrap
```

```powershell
./build.ps1
```

Der erste Befehl installiert Pester 5 und PSScriptAnalyzer, der zweite führt Analyse, Doku-Check und Tests aus. Alles Weitere steht in [CONTRIBUTING.md](CONTRIBUTING.md) (Englisch).

## Credits

Erstellt von **Matej**, mit Unterstützung von [Claude](https://claude.ai) (Anthropic) als KI-Coding-Assistent.
Regel-Recherche, Code-Reviews und Security-Audit wurden mit Claude gemacht und gegen offizielle Microsoft-Quellen geprüft.

## Lizenz

[MIT](LICENSE).

Disclaimer: not affiliated with Microsoft. Dieses Projekt steht in keiner Verbindung zu Microsoft und wird nicht von Microsoft unterstützt. Produktnamen sind Marken ihrer jeweiligen Inhaber.
