<#
.SYNOPSIS
    Active (ou desactive) l'ouverture de session automatique de Windows DANS la VM.

    Pourquoi c'est necessaire au streaming : tant que personne n'a ouvert de
    session dans l'invite, Windows refuse toute modification de la configuration
    d'affichage (SetDisplayConfig repond ERROR_ACCESS_DENIED). Sunshine ne peut
    alors ni activer l'ecran virtuel VDD, ni lui appliquer la resolution et la
    frequence demandees : on diffuse un ecran virtuel vide, donc noir. Une VM qui
    ouvre sa session toute seule au demarrage n'a jamais ce probleme - c'est le
    montage habituel d'une machine dediee au streaming.

    Le mot de passe n'est PAS ecrit en clair dans le registre. Windows sait lire
    un secret LSA nomme "DefaultPassword" : c'est ce qu'utilise l'outil Autologon
    de Sysinternals, et ce que fait ce script (LsaStorePrivateData). La valeur
    "DefaultPassword" du registre, elle, est explicitement supprimee si une
    execution precedente ou un autre outil l'avait laissee.

    A savoir, et assume : une VM en ouverture automatique demarre directement sur
    le bureau. Quiconque a acces a sa console y entre sans mot de passe. C'est le
    prix de "demarrer la VM et streamer en un clic".

    Securite : les identifiants Windows de la VM sont lus sur l'ENTREE STANDARD
    uniquement (jamais en argument, jamais journalises) - voir
    PowerShellRunner.RunWithCredentialAsync cote C#.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    # "true" pour retirer l'ouverture automatique.
    [string]$Disable = "false"
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

$disableBool = $Disable -eq "true"

Invoke-NovaAction {
    $username = [Console]::In.ReadLine()
    $passwordPlain = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($passwordPlain)) {
        throw "Identifiants manquants (nom d'utilisateur ou mot de passe vide)."
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour configurer l'ouverture de session automatique (PowerShell Direct)."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    Write-NovaProgress "Configuration de l'ouverture de session dans la VM"
    $outcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop `
        -ArgumentList $username, $passwordPlain, $disableBool -ScriptBlock {
        param($User, $Password, $Disable)

        $winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

        if ($Disable) {
            Set-ItemProperty -Path $winlogon -Name "AutoAdminLogon" -Value "0" -Type String
            Remove-ItemProperty -Path $winlogon -Name "DefaultPassword" -ErrorAction SilentlyContinue
            return [ordered]@{ enabled = $false; account = $null; secretStored = $false }
        }

        # Un compte Microsoft s'ouvre avec un domaine special ; un compte local
        # avec le nom de la machine. Le prefixe eventuel est retire du nom lui-meme.
        $account = $User
        $domain = $env:COMPUTERNAME
        if ($account -like "MicrosoftAccount\*") {
            $account = $account.Substring("MicrosoftAccount\".Length)
            $domain = "MicrosoftAccount"
        } elseif ($account -like "*\*") {
            $parts = $account.Split('\', 2)
            $domain = $parts[0]
            $account = $parts[1]
        } elseif ($account -like "*@*") {
            $domain = "MicrosoftAccount"
        }

        Set-ItemProperty -Path $winlogon -Name "AutoAdminLogon" -Value "1" -Type String
        Set-ItemProperty -Path $winlogon -Name "DefaultUserName" -Value $account -Type String
        Set-ItemProperty -Path $winlogon -Name "DefaultDomainName" -Value $domain -Type String

        # Jamais de mot de passe en clair dans le registre : si une valeur
        # DefaultPassword traine (autre outil, execution precedente), on l'efface.
        Remove-ItemProperty -Path $winlogon -Name "DefaultPassword" -ErrorAction SilentlyContinue
        # AutoLogonCount se decremente a chaque demarrage et desactiverait
        # l'ouverture automatique au bout de n demarrages.
        Remove-ItemProperty -Path $winlogon -Name "AutoLogonCount" -ErrorAction SilentlyContinue

        # Windows 11 propose par defaut la connexion "sans mot de passe" (Hello),
        # qui empeche l'ouverture automatique. Ce reglage la remet a disposition.
        $passwordless = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
        if (-not (Test-Path $passwordless)) { New-Item -Path $passwordless -Force | Out-Null }
        Set-ItemProperty -Path $passwordless -Name "DevicePasswordLessBuildVersion" -Value 0 -Type DWord

        # Secret LSA "DefaultPassword" : c'est la ou Windows va chercher le mot de
        # passe d'ouverture automatique quand le registre n'en contient pas. Stocke
        # chiffre par le systeme, contrairement a la valeur de registre.
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class NovaLsa
{
    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_OBJECT_ATTRIBUTES
    {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public int Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct LSA_UNICODE_STRING
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaOpenPolicy(
        IntPtr systemName, ref LSA_OBJECT_ATTRIBUTES objectAttributes, uint desiredAccess, out IntPtr policyHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint LsaStorePrivateData(
        IntPtr policyHandle, ref LSA_UNICODE_STRING keyName, ref LSA_UNICODE_STRING privateData);

    [DllImport("advapi32.dll")]
    private static extern uint LsaClose(IntPtr objectHandle);

    [DllImport("advapi32.dll")]
    private static extern int LsaNtStatusToWinError(uint status);

    private static LSA_UNICODE_STRING ToLsaString(string value)
    {
        var result = new LSA_UNICODE_STRING();
        result.Buffer = Marshal.StringToHGlobalUni(value);
        result.Length = (ushort)(value.Length * 2);
        result.MaximumLength = (ushort)((value.Length + 1) * 2);
        return result;
    }

    private static void FreeLsaString(ref LSA_UNICODE_STRING value, int charCount)
    {
        if (value.Buffer == IntPtr.Zero) return;
        // Le tampon est efface avant liberation : un mot de passe ne doit pas
        // rester lisible dans la memoire rendue au tas.
        for (int i = 0; i < charCount; i++) Marshal.WriteInt16(value.Buffer, i * 2, 0);
        Marshal.FreeHGlobal(value.Buffer);
        value.Buffer = IntPtr.Zero;
    }

    /// <summary>0 si le secret a bien ete enregistre, code d'erreur Win32 sinon.</summary>
    public static int Store(string key, string value)
    {
        var attributes = new LSA_OBJECT_ATTRIBUTES();
        attributes.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));

        IntPtr policy;
        const uint POLICY_CREATE_SECRET = 0x00000020;
        var status = LsaOpenPolicy(IntPtr.Zero, ref attributes, POLICY_CREATE_SECRET, out policy);
        if (status != 0) return LsaNtStatusToWinError(status);

        var keyString = ToLsaString(key);
        var valueString = ToLsaString(value);
        try
        {
            status = LsaStorePrivateData(policy, ref keyString, ref valueString);
            return LsaNtStatusToWinError(status);
        }
        finally
        {
            FreeLsaString(ref keyString, key.Length);
            FreeLsaString(ref valueString, value.Length);
            LsaClose(policy);
        }
    }
}
"@
        $code = [NovaLsa]::Store("DefaultPassword", $Password)
        if ($code -ne 0) {
            throw "Windows a refuse d'enregistrer le secret d'ouverture automatique (code $code). L'ouverture de session automatique n'a pas ete activee."
        }

        [ordered]@{ enabled = $true; account = "$domain\$account"; secretStored = $true }
    }

    $result = [ordered]@{
        enabled      = [bool]$outcome.enabled
        account      = $outcome.account
        secretStored = [bool]$outcome.secretStored
        message      = if ($outcome.enabled) {
            "La VM ouvrira sa session Windows automatiquement au demarrage ($($outcome.account)). Le mot de passe est garde par Windows dans un secret LSA chiffre, jamais en clair dans le registre. Effet de bord assume : la VM demarre directement sur le bureau, sans demander de mot de passe."
        } else {
            "Ouverture de session automatique desactivee : la VM redemandera son mot de passe au demarrage."
        }
    }
    Write-NovaResult -Success $true -DataJson ([pscustomobject]$result | ConvertTo-Json -Compress)
}
