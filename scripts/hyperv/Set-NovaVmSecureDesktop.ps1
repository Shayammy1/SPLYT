<#
.SYNOPSIS
    Affiche les demandes d'elevation de la VM sur son bureau ordinaire plutot que
    sur le bureau securise, pour qu'elles traversent le flux de jeu.

    Le probleme : quand Windows demande des droits administrateur, il bascule sur
    un BUREAU SECURISE, une surface d'affichage isolee que rien ne peut capturer -
    Sunshine pas plus qu'un autre. Le flux se fige donc sur sa derniere image tant
    que l'invite est affichee, et le clavier et la souris envoyes par Moonlight
    ne l'atteignent pas davantage. D'ou des gels de quelques secondes a une demi-
    minute a chaque installation de logiciel dans la VM.

    Le remede : demander a Windows de poser l'invite sur le bureau ordinaire. Elle
    est alors capturee comme le reste, visible dans le flux, et cliquable a
    distance.

    CE QU'ON PERD. Le bureau securise existe pour qu'aucun autre logiciel de la
    session ne puisse ni lire l'invite de consentement, ni cliquer a votre place.
    Le desactiver abaisse cette protection A L'INTERIEUR DE LA VM, et nulle part
    ailleurs : l'hote n'est pas touche. Sur une VM de jeu dediee le compromis est
    courant - c'est ce que recommande la documentation de Sunshine - mais c'est un
    choix a faire en connaissance de cause, jamais un reglage a appliquer en
    douce. D'ou ce script separe, et reversible.

    Securite : identifiants lus sur l'ENTREE STANDARD, jamais en argument ni dans
    un journal.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    # true = retablir le bureau securise, false = poser l'invite sur le bureau
    # ordinaire (donc visible dans le flux).
    [Parameter(Mandatory)][ValidateSet('true','false')][string]$SecureDesktop
)

Import-Module (Join-Path $PSScriptRoot "NovaVm.Common.psm1") -Force

Invoke-NovaAction {
    $username = [Console]::In.ReadLine()
    $passwordPlain = [Console]::In.ReadLine()
    if ([string]::IsNullOrEmpty($username) -or [string]::IsNullOrEmpty($passwordPlain)) {
        throw "Identifiants manquants (nom d'utilisateur ou mot de passe vide)."
    }

    $vm = Get-VM -Name $Name -ErrorAction Stop
    if ($vm.State -ne 'Running') {
        throw "La VM doit etre demarree pour modifier ce reglage."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)
    $wantSecure = $SecureDesktop -eq 'true'

    $outcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ArgumentList $wantSecure -ScriptBlock {
        param($wantSecure)

        $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $before = (Get-ItemProperty -Path $key -Name PromptOnSecureDesktop -ErrorAction SilentlyContinue).PromptOnSecureDesktop

        Set-ItemProperty -Path $key -Name PromptOnSecureDesktop -Value ([int]$wantSecure) -Type DWord -ErrorAction Stop

        $after = (Get-ItemProperty -Path $key -Name PromptOnSecureDesktop -ErrorAction SilentlyContinue).PromptOnSecureDesktop
        [pscustomobject]@{
            before = [int]$before
            after  = [int]$after
        }
    }

    if ([int]$outcome.after -ne [int]$wantSecure) {
        throw "Le reglage n'a pas ete applique (valeur lue : $($outcome.after))."
    }

    # Aucun redemarrage a demander : consent.exe relit ce reglage a chaque
    # demande d'elevation, le changement vaut donc pour la prochaine.
    $message = if ($wantSecure) {
        "Bureau securise retabli dans la VM : les demandes d'administrateur y figeront a nouveau le flux."
    } else {
        "Les demandes d'administrateur de la VM s'afficheront dans le flux, sans le figer. Elles ne sont plus protegees par le bureau securise, a l'interieur de la VM uniquement."
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        secureDesktop = $wantSecure
        previousValue = [int]$outcome.before
        message       = $message
    } | ConvertTo-Json -Compress)
}
