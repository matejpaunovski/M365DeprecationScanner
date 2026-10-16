function New-DeprecationFinding {
    <#
    .SYNOPSIS
        Builds the finding object returned to the user.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Only creates an in-memory object.')]
    [CmdletBinding()]
    [OutputType('M365DeprecationScanner.Finding')]
    param(
        [Parameter(Mandatory)]
        [object]$Rule,

        [Parameter(Mandatory)]
        [System.Management.Automation.Language.IScriptExtent]$Extent,

        [Parameter(Mandatory)]
        [string]$MatchText,

        [AllowNull()]
        [string]$FilePath
    )

    $message = '{0} Use {1} instead.' -f $Rule.Title.TrimEnd(), $Rule.Replacement
    if ($Rule.RetirementDate) {
        $message += ' (Retirement: {0})' -f $Rule.RetirementDate
    }

    [pscustomobject]@{
        PSTypeName        = 'M365DeprecationScanner.Finding'
        RuleId            = $Rule.Id
        Severity          = $Rule.Severity
        Status            = $Rule.Status
        Area              = $Rule.Area
        Kind              = $Rule.Kind
        Match             = $MatchText
        Title             = $Rule.Title
        Replacement       = $Rule.Replacement
        ReplacementModule = $Rule.ReplacementModule
        Notes             = $Rule.Notes
        RetirementDate    = $Rule.RetirementDate
        Sources           = $Rule.Sources
        Message           = $message
        Path              = $FilePath
        Line              = $Extent.StartLineNumber
        Column            = $Extent.StartColumnNumber
        EndLine           = $Extent.EndLineNumber
        EndColumn         = $Extent.EndColumnNumber
        LineText          = $Extent.StartScriptPosition.Line.Trim()
        Extent            = $Extent
    }
}
