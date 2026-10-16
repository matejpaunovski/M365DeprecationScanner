function Find-DeprecationInAst {
    <#
    .SYNOPSIS
        Core engine: walks a parsed script and returns a finding for every deprecated item.
    .DESCRIPTION
        Looks at four things in the syntax tree, matching the four rule kinds:
          * Command       - every command invocation (Get-MsolUser, MSOnline\Get-MsolUser, ...)
          * Parameter     - parameters on a command (Connect-ExchangeOnline -UseRPSSession)
          * Module        - Import-Module / Install-Module / #Requires -Modules / using module
          * StringLiteral - string literals such as URLs ('https://graph.windows.net/...')
        Comments are never flagged. Suppression comments (m365ds-ignore...) are honoured when tokens are passed.
    #>
    [CmdletBinding()]
    [OutputType('M365DeprecationScanner.Finding')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules,

        [AllowNull()]
        [System.Management.Automation.Language.Token[]]$Tokens,

        [AllowNull()]
        [string]$FilePath
    )

    # Findings are collected first and returned sorted by position in the file.
    @(Find-DeprecationInAstUnsorted @PSBoundParameters) |
        Sort-Object -Property Line, Column, RuleId
}

function Find-DeprecationInAstUnsorted {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'FilePath', Justification = 'Used inside the $emit script block.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules,

        [AllowNull()]
        [System.Management.Automation.Language.Token[]]$Tokens,

        [AllowNull()]
        [string]$FilePath
    )

    $commandIndex = New-RuleIndex -Rules @($Rules | Where-Object { $_.Kind -eq 'Command' })
    $moduleIndex = New-RuleIndex -Rules @($Rules | Where-Object { $_.Kind -eq 'Module' })
    $parameterRules = @($Rules | Where-Object { $_.Kind -eq 'Parameter' })
    $stringRules = @($Rules | Where-Object { $_.Kind -eq 'StringLiteral' })

    $suppressions = Get-SuppressionMap -Tokens $Tokens
    $emitted = @{}

    # Small local helper so every finding goes through suppression + de-duplication.
    $emit = {
        param($Rule, $Extent, [string]$MatchText)
        $key = '{0}|{1}|{2}' -f $Rule.Id, $Extent.StartOffset, $MatchText
        if ($emitted.ContainsKey($key)) { return }
        $emitted[$key] = $true
        if (Test-Suppressed -SuppressionMap $suppressions -Line $Extent.StartLineNumber -RuleId $Rule.Id) { return }
        New-DeprecationFinding -Rule $Rule -Extent $Extent -MatchText $MatchText -FilePath $FilePath
    }

    $moduleCommands = @(
        'Import-Module', 'Install-Module', 'Update-Module', 'Save-Module',
        'Install-PSResource', 'Update-PSResource', 'Save-PSResource'
    )
    # Commands that write module dependencies into a manifest.
    $manifestCommands = @('New-ModuleManifest', 'Update-ModuleManifest')

    # Walk the syntax tree once and sort the interesting nodes by type. The predicate runs for every
    # node, so a single pass is much faster than one FindAll per node type on large scripts.
    $commandAsts = New-Object System.Collections.Generic.List[object]
    $usingAsts = New-Object System.Collections.Generic.List[object]
    $stringAsts = New-Object System.Collections.Generic.List[object]
    $hashtableAsts = New-Object System.Collections.Generic.List[object]
    $nodes = $Ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -or
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $node -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
            $node -is [System.Management.Automation.Language.UsingStatementAst] -or
            $node -is [System.Management.Automation.Language.HashtableAst]
        }, $true)
    foreach ($node in $nodes) {
        if ($node -is [System.Management.Automation.Language.CommandAst]) { $commandAsts.Add($node) }
        elseif ($node -is [System.Management.Automation.Language.UsingStatementAst]) { $usingAsts.Add($node) }
        elseif ($node -is [System.Management.Automation.Language.HashtableAst]) { $hashtableAsts.Add($node) }
        else { $stringAsts.Add($node) }
    }

    # --- Commands, parameters and module-loading commands -------------------------------
    foreach ($commandAst in $commandAsts) {
        $commandName = $commandAst.GetCommandName()
        if ([string]::IsNullOrEmpty($commandName)) {
            continue
        }
        # Strip a module qualifier: MSOnline\Get-MsolUser -> Get-MsolUser
        $bareName = $commandName.Substring($commandName.LastIndexOf('\') + 1)
        $nameElement = $commandAst.CommandElements[0]

        # Fast path: most commands (Get-ChildItem, Where-Object, ...) match no rule at all. Checking that
        # inline avoids an advanced-function call per command, which dominates the run time.
        $possible = $commandIndex.Exact.ContainsKey($bareName)
        if (-not $possible) {
            foreach ($wildcardRule in $commandIndex.Wildcards) {
                if ($wildcardRule.Matcher.IsMatch($bareName)) { $possible = $true; break }
            }
        }
        if ($possible) {
            $rule = Select-MatchingRule -Index $commandIndex -Name $bareName
            if ($rule) {
                & $emit $rule $nameElement.Extent $commandName
            }
        }

        if ($parameterRules.Count -gt 0) {
            foreach ($parameterAst in $commandAst.CommandElements) {
                if ($parameterAst -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                    continue
                }
                # '-Switch:$false' explicitly turns the deprecated switch off - that is fine.
                $argument = $parameterAst.Argument
                if ($argument -is [System.Management.Automation.Language.VariableExpressionAst] -and $argument.VariablePath.UserPath -eq 'false') {
                    continue
                }
                foreach ($rule in $parameterRules) {
                    if ($rule.CommandMatcher.IsMatch($bareName) -and $rule.Matcher.IsMatch($parameterAst.ParameterName)) {
                        & $emit $rule $parameterAst.Extent ('{0} -{1}' -f $bareName, $parameterAst.ParameterName)
                    }
                }
            }
        }

        if ($moduleIndex.Count -gt 0 -and $moduleCommands -contains $bareName) {
            foreach ($moduleArgument in Get-ModuleNameArgument -CommandAst $commandAst) {
                $rule = Select-MatchingRule -Index $moduleIndex -Name $moduleArgument.Name
                if ($rule) {
                    & $emit $rule $moduleArgument.Extent ('{0} {1}' -f $bareName, $moduleArgument.Name)
                }
            }
        }

        # New-ModuleManifest -RequiredModules 'AzureAD' writes the dependency into a manifest.
        if ($moduleIndex.Count -gt 0 -and $manifestCommands -contains $bareName) {
            $elements = $commandAst.CommandElements
            for ($i = 1; $i -lt $elements.Count; $i++) {
                $parameterAst = $elements[$i]
                if ($parameterAst -isnot [System.Management.Automation.Language.CommandParameterAst] -or
                    $parameterAst.ParameterName -notin 'RequiredModules', 'NestedModules') {
                    continue
                }
                $value = $parameterAst.Argument
                if (-not $value -and $i + 1 -lt $elements.Count) { $value = $elements[$i + 1] }
                if (-not $value) { continue }
                foreach ($module in Get-ModuleSpecificationName -Ast $value) {
                    $rule = Select-MatchingRule -Index $moduleIndex -Name $module.Name
                    if ($rule) {
                        & $emit $rule $module.Extent ('{0} -{1} {2}' -f $bareName, $parameterAst.ParameterName, $module.Name)
                    }
                }
            }
        }
    }

    if ($moduleIndex.Count -gt 0) {
        # --- using module X ----------------------------------------------------------------
        foreach ($usingAst in $usingAsts) {
            if ($usingAst.UsingStatementKind -ne [System.Management.Automation.Language.UsingStatementKind]::Module -or $null -eq $usingAst.Name) {
                continue
            }
            $rule = Select-MatchingRule -Index $moduleIndex -Name $usingAst.Name.Value
            if ($rule) {
                & $emit $rule $usingAst.Extent ('using module {0}' -f $usingAst.Name.Value)
            }
        }

        # --- Module manifests (.psd1): RequiredModules / NestedModules -----------------------
        # A manifest is a hashtable at the top level of the file. Hashtables assigned to variables
        # or passed to commands are ordinary data and are not treated as manifests.
        foreach ($hashtableAst in $hashtableAsts) {
            if (-not (Test-TopLevelHashtable -Ast $hashtableAst)) {
                continue
            }
            foreach ($pair in $hashtableAst.KeyValuePairs) {
                $key = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
                if (-not $key -or $key.Value -notin 'RequiredModules', 'NestedModules') {
                    continue
                }
                foreach ($module in Get-ModuleSpecificationName -Ast $pair.Item2) {
                    $rule = Select-MatchingRule -Index $moduleIndex -Name $module.Name
                    if ($rule) {
                        & $emit $rule $module.Extent ('{0} {1}' -f $key.Value, $module.Name)
                    }
                }
            }
        }

        # --- #Requires -Modules X ----------------------------------------------------------
        $scriptBlockAst = $Ast -as [System.Management.Automation.Language.ScriptBlockAst]
        if ($scriptBlockAst -and $scriptBlockAst.ScriptRequirements) {
            foreach ($requiredModule in $scriptBlockAst.ScriptRequirements.RequiredModules) {
                $rule = Select-MatchingRule -Index $moduleIndex -Name $requiredModule.Name
                if ($rule) {
                    $extent = Get-RequiresExtent -Tokens $Tokens -ModuleName $requiredModule.Name -Fallback $scriptBlockAst.Extent
                    & $emit $rule $extent ('#Requires -Modules {0}' -f $requiredModule.Name)
                }
            }
        }
    }

    # --- String literals (endpoints, URLs) ---------------------------------------------------
    if ($stringRules.Count -gt 0) {
        foreach ($stringAst in $stringAsts) {
            $value = $stringAst.Value
            if ([string]::IsNullOrEmpty($value)) {
                continue
            }
            $skipChecked = $false
            foreach ($rule in $stringRules) {
                $match = $null
                try {
                    $match = $rule.Regex.Match($value)
                }
                catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
                    Write-Warning "Rule $($rule.Id): regular expression timed out on a string at line $($stringAst.Extent.StartLineNumber); skipped."
                }
                if (-not ($match -and $match.Success)) {
                    continue
                }
                # Only strings that match pay for these checks (most strings match nothing).
                if (-not $skipChecked) {
                    $skipChecked = $true
                    # The command name itself (Get-Foo) is also a StringConstantExpressionAst - skip it.
                    $parent = $stringAst.Parent
                    $isCommandName = $parent -is [System.Management.Automation.Language.CommandAst] -and [object]::ReferenceEquals($parent.CommandElements[0], $stringAst)
                    # Strings nested inside "...$('x')..." are already covered by the outer expandable string.
                    if ($isCommandName -or (Test-InsideExpandableString -Ast $stringAst)) {
                        break
                    }
                }
                & $emit $rule $stringAst.Extent $match.Value
            }
        }
    }
}

function Get-ModuleNameArgument {
    <#
    .SYNOPSIS
        Extracts literal module names (with their extents) from Import-Module / Install-Module calls.
    .DESCRIPTION
        Handles '-Name X', '-Name:X', positional 'X' and lists 'X, Y'. Dynamic values such as
        variables cannot be resolved statically and are ignored.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.CommandAst]$CommandAst
    )

    # Parameters of the module cmdlets that take a value; their argument is never the module name.
    $valueParameters = @(
        'RequiredVersion', 'MinimumVersion', 'MaximumVersion', 'Version', 'Scope', 'Repository',
        'Prefix', 'Credential', 'Proxy', 'ProxyCredential', 'ArgumentList', 'Function', 'Cmdlet',
        'Alias', 'Variable', 'PSSession', 'CimSession', 'CimResourceUri', 'CimNamespace',
        'Path', 'LiteralPath', 'DestinationPath', 'InputObject', 'FullyQualifiedName', 'Assembly',
        'ModuleInfo', 'TemporaryPath', 'Args', 'ProgressAction',
        'ErrorAction', 'WarningAction', 'ErrorVariable', 'WarningVariable', 'OutVariable', 'OutBuffer',
        'PipelineVariable', 'InformationAction', 'InformationVariable',
        'EA', 'WA', 'EV', 'WV', 'OV', 'OB', 'PV', 'IA', 'IV', 'Proga'
    )

    $elements = $CommandAst.CommandElements
    $nameExpressions = New-Object System.Collections.Generic.List[object]
    $sawNameParameter = $false
    $positionalTaken = $false

    for ($i = 1; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($element.ParameterName -in 'Name', 'ModuleName') {
                $sawNameParameter = $true
                if ($element.Argument) {
                    $nameExpressions.Add($element.Argument)
                }
                elseif ($i + 1 -lt $elements.Count) {
                    $nameExpressions.Add($elements[$i + 1])
                    $i++
                }
            }
            elseif (-not $element.Argument -and $valueParameters -contains $element.ParameterName) {
                $i++   # skip the parameter's value
            }
            continue
        }
        if (-not $positionalTaken -and -not $sawNameParameter) {
            $nameExpressions.Add($element)
            $positionalTaken = $true
        }
    }

    foreach ($expression in $nameExpressions) {
        foreach ($candidate in Get-LiteralElement -Ast $expression) {
            if ($candidate -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $candidate.Value) {
                [pscustomobject]@{ Name = $candidate.Value; Extent = $candidate.Extent }
            }
        }
    }
}

function Get-RequiresExtent {
    <#
    .SYNOPSIS
        Finds the '#Requires' comment that mentions a module so the finding points at the right line.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Management.Automation.Language.Token[]]$Tokens,

        [Parameter(Mandatory)]
        [string]$ModuleName,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.IScriptExtent]$Fallback
    )

    if ($Tokens) {
        $escapedName = [regex]::Escape($ModuleName)
        foreach ($token in $Tokens) {
            if ($token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment -and
                $token.Text -match '^#requires\b' -and $token.Text -match "(?<![\w.-])$escapedName(?![\w.-])") {
                return $token.Extent
            }
        }
    }
    return $Fallback
}


function Get-LiteralElement {
    <#
    .SYNOPSIS
        Unwraps 'X, Y', @('X'), ('X') and @('X', 'Y') to the individual element expressions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    if ($Ast -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        foreach ($element in $Ast.Elements) { Get-LiteralElement -Ast $element }
    }
    elseif ($Ast -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        foreach ($statement in $Ast.SubExpression.Statements) { Get-LiteralElement -Ast $statement }
    }
    elseif ($Ast -is [System.Management.Automation.Language.ParenExpressionAst]) {
        Get-LiteralElement -Ast $Ast.Pipeline
    }
    elseif ($Ast -is [System.Management.Automation.Language.PipelineAst] -and $Ast.PipelineElements.Count -eq 1 -and
        $Ast.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
        Get-LiteralElement -Ast $Ast.PipelineElements[0].Expression
    }
    else {
        $Ast
    }
}

function Test-InsideExpandableString {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    for ($node = $Ast.Parent; $null -ne $node; $node = $node.Parent) {
        if ($node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            return $true
        }
    }
    return $false
}


function Get-ModuleSpecificationName {
    <#
    .SYNOPSIS
        Returns module names from a module specification list, as used in manifests.
    .DESCRIPTION
        Accepts what RequiredModules / NestedModules allow: 'Name', @('A', 'B') and
        @{ ModuleName = 'Name'; ModuleVersion = '1.0' }. Only literal names are returned.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )

    foreach ($element in Get-LiteralElement -Ast $Ast) {
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $element.Value) {
            [pscustomobject]@{ Name = $element.Value; Extent = $element.Extent }
        }
        elseif ($element -is [System.Management.Automation.Language.HashtableAst]) {
            foreach ($pair in $element.KeyValuePairs) {
                $key = $pair.Item1 -as [System.Management.Automation.Language.StringConstantExpressionAst]
                if (-not $key -or $key.Value -ne 'ModuleName') {
                    continue
                }
                foreach ($value in Get-LiteralElement -Ast $pair.Item2) {
                    if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $value.Value) {
                        [pscustomobject]@{ Name = $value.Value; Extent = $value.Extent }
                    }
                }
            }
        }
    }
}

function Test-TopLevelHashtable {
    <#
    .SYNOPSIS
        True when a hashtable is a statement of its own at the top level of the file (manifest shape).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.HashtableAst]$Ast
    )

    $expression = $Ast.Parent -as [System.Management.Automation.Language.CommandExpressionAst]
    if (-not $expression) { return $false }
    $pipeline = $expression.Parent -as [System.Management.Automation.Language.PipelineAst]
    if (-not $pipeline -or $pipeline.PipelineElements.Count -ne 1) { return $false }
    $namedBlock = $pipeline.Parent -as [System.Management.Automation.Language.NamedBlockAst]
    if (-not $namedBlock) { return $false }
    $scriptBlock = $namedBlock.Parent -as [System.Management.Automation.Language.ScriptBlockAst]
    return ($null -ne $scriptBlock -and $null -eq $scriptBlock.Parent)
}
