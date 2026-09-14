<#
.SYNOPSIS
    Choisit la manette que Sunshine fait apparaitre DANS LA VM, en ecrivant la
    cle "gamepad" de sunshine.conf, puis redemarre Sunshine pour l'appliquer.

    Pourquoi ce reglage compte : laisse sur "auto", Sunshine emule une
    DualShock 4 des qu'il detecte un pave tactile ou des capteurs de mouvement
    cote client - ce que fait justement une DualSense. Or une DS4 est un
    peripherique DirectInput/HID, pas XInput : les jeux qui ne gerent que XInput
    ne la voient pas du tout. "x360" garantit au contraire une manette XInput,
    reconnue partout.

    -GamepadProfile "read" se contente de lire la valeur en place, sans rien
    modifier :
    c'est ce qui permet a l'interface d'afficher l'etat reel plutot qu'une
    valeur devinee.

    Securite : identifiants lus sur l'ENTREE STANDARD, jamais en argument ni
    dans un journal.
#>
param(
    [Parameter(Mandatory)][string]$Name,
    # "read" = ne rien changer, juste rapporter. Les autres valeurs sont celles
    # que Sunshine accepte reellement (relevees dans son binaire).
    [Parameter(Mandatory)][ValidateSet('read','auto','x360','xone','ds4','switch')][string]$GamepadProfile
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
        throw "La VM doit etre demarree pour s'y connecter (PowerShell Direct)."
    }

    $securePassword = ConvertTo-SecureString -String $passwordPlain -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

    Write-NovaProgress "Connexion a la VM (PowerShell Direct)"
    $outcome = Invoke-Command -VMName $Name -Credential $credential -ErrorAction Stop -ArgumentList $GamepadProfile -ScriptBlock {
        # Surtout pas $profile : c'est une variable automatique de PowerShell (le
        # chemin du fichier de profil). La masquer marche, mais c'est un piege
        # pose pour plus tard.
        param($choix)

        $step = "recherche de la configuration de Sunshine"
        $configPath = "C:\Program Files\Sunshine\config\sunshine.conf"
        if (-not (Test-Path -LiteralPath $configPath)) {
            return [pscustomobject]@{
                Success      = $false
                Step         = $step
                ErrorMessage = "sunshine.conf est introuvable dans la VM : Sunshine n'y est pas installe."
            }
        }

        try {
            $step = "lecture de la valeur en place"
            $lignes = @(Get-Content -LiteralPath $configPath -ErrorAction Stop)

            # Absente du fichier, la cle vaut "auto" : c'est le defaut de Sunshine,
            # et il n'ecrit que ce qui a ete change.
            $courant = "auto"
            $indexLigne = -1
            for ($i = 0; $i -lt $lignes.Count; $i++) {
                if ($lignes[$i] -match '^\s*gamepad\s*=\s*(\S+)\s*$') {
                    $courant = $Matches[1]
                    $indexLigne = $i
                    break
                }
            }

            if ($choix -eq 'read') {
                return [pscustomobject]@{
                    Success  = $true
                    Current  = $courant
                    Changed  = $false
                    Restarted = $false
                    Step     = $null
                    ErrorMessage = $null
                }
            }

            if ($courant -eq $choix) {
                return [pscustomobject]@{
                    Success   = $true
                    Current   = $courant
                    Changed   = $false
                    Restarted = $false
                    Step      = $null
                    ErrorMessage = $null
                }
            }

            $step = "ecriture du reglage"
            $nouvelleLigne = "gamepad = $choix"
            if ($indexLigne -ge 0) {
                $lignes[$indexLigne] = $nouvelleLigne
            } else {
                $lignes += $nouvelleLigne
            }
            Set-Content -LiteralPath $configPath -Value $lignes -Encoding UTF8 -ErrorAction Stop

            # Sunshine ne relit sa configuration qu'au demarrage : sans ce
            # redemarrage, le reglage ne prendrait effet qu'au prochain allumage de
            # la VM, et l'utilisateur croirait le bouton sans effet.
            $step = "redemarrage de Sunshine"
            $restarted = $false
            $service = Get-Service -Name "SunshineService" -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq 'Running') {
                try {
                    Restart-Service -Name "SunshineService" -Force -ErrorAction Stop
                    $restarted = $true
                } catch { }
            }

            return [pscustomobject]@{
                Success      = $true
                Current      = $choix
                Changed      = $true
                Restarted    = $restarted
                Step         = $null
                ErrorMessage = $null
            }
        } catch {
            return [pscustomobject]@{
                Success      = $false
                Step         = $step
                ErrorMessage = $_.Exception.Message
            }
        }
    }

    if (-not $outcome.Success) {
        throw "Echec a l'etape '$($outcome.Step)' dans la VM : $($outcome.ErrorMessage)"
    }

    $libelles = @{
        auto   = "automatique"
        x360   = "Xbox 360"
        xone   = "Xbox One"
        ds4    = "DualShock 4"
        switch = "manette Switch"
    }
    $nom = if ($libelles.ContainsKey("$($outcome.Current)")) { $libelles["$($outcome.Current)"] } else { "$($outcome.Current)" }

    $message = if (-not $outcome.Changed) {
        "Manette emulee dans la VM : $nom (deja en place)."
    } elseif ($outcome.Restarted) {
        "Manette emulee dans la VM : $nom. Sunshine redemarre, le reglage est actif."
    } else {
        "Manette emulee dans la VM : $nom. Relancez le mode jeu pour l'appliquer."
    }

    Write-NovaResult -Success $true -DataJson ([pscustomobject]@{
        current   = "$($outcome.Current)"
        changed   = [bool]$outcome.Changed
        restarted = [bool]$outcome.Restarted
        message   = $message
    } | ConvertTo-Json -Compress)
}
