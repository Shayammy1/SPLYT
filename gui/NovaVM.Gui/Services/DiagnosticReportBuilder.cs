using System.Text;
using System.Text.RegularExpressions;
using NovaVM.Gui.Models;
using NovaVM.Gui.Services.PowerShell;

namespace NovaVM.Gui.Services;

/// <summary>
/// Assemble un rapport de diagnostic prêt a coller dans un rapport de bug.
///
/// Pourquoi : deux pannes GPU-P de causes totalement differentes donnent le meme
/// symptome vu de l'exterieur ("le GPU-P ne marche pas") - c'est arrive deux fois
/// sur ce projet, une fois par des fichiers de pilote manquants, une fois par un
/// espace MMIO trop grand. Seuls le modele exact de GPU, sa version de pilote, la
/// build de Windows et l'etape precise permettent de les distinguer. Demander tout
/// ca a l'utilisateur donne des champs oublies ou faux ; SPLYT le sait deja.
///
/// Ce texte est destine a etre publie (issue GitHub) : les chemins contenant un
/// profil utilisateur sont donc masques, et rien de sensible n'y figure - aucun
/// identifiant de VM n'est manipule ici (ils vivent dans le Gestionnaire
/// d'identifiants Windows, voir VmCredentialStore).
/// </summary>
public static class DiagnosticReportBuilder
{
    public static string Build(
        string appVersion,
        DiagnosticsDto? diagnostics,
        HostLimits hostLimits,
        IReadOnlyList<HostGpu> gpus,
        IReadOnlyList<VirtualMachine> vms,
        IEnumerable<LogEntry> recentAlerts)
    {
        var report = new StringBuilder();

        report.AppendLine("### SPLYT - rapport de diagnostic");
        report.AppendLine();
        report.AppendLine($"- SPLYT : {appVersion}");
        report.AppendLine($"- Windows : {Or(diagnostics?.OsCaption)} {Or(diagnostics?.OsDisplayVersion)} (build {Or(diagnostics?.OsBuild)})");
        report.AppendLine($"- Processeur : {Or(diagnostics?.CpuName)} - {hostLimits.CpuCores} coeurs / {hostLimits.CpuLogicalProcessors} threads");
        report.AppendLine($"- RAM : {hostLimits.TotalPhysicalGb} Go");
        report.AppendLine();

        report.AppendLine("**GPU de l'hote**");
        if (gpus.Count == 0)
        {
            report.AppendLine("- aucun GPU detecte");
        }
        else
        {
            foreach (var gpu in gpus)
            {
                var vram = gpu.VramBytes > 0 ? $"{gpu.VramGb} Go VRAM dediee" : "pas de VRAM dediee (GPU integre)";
                report.AppendLine($"- {gpu.Name} - pilote {Or(gpu.DriverVersion)} - {vram} - GPU-P : {YesNo(gpu.PartitionSupported)}");
                if (!string.IsNullOrWhiteSpace(gpu.PartitionCheckError))
                {
                    report.AppendLine($"  - erreur de verification GPU-P : {Redact(gpu.PartitionCheckError)}");
                }
            }
        }
        report.AppendLine();

        report.AppendLine("**Hyper-V**");
        if (diagnostics is null)
        {
            report.AppendLine("- diagnostic indisponible (le script n'a pas repondu)");
        }
        else
        {
            report.AppendLine($"- module Hyper-V : {YesNo(diagnostics.HyperVModuleInstalled)} {Or(diagnostics.HyperVModuleVersion)}");
            report.AppendLine($"- listage des VMs : {YesNo(diagnostics.CanListVms)}");
            if (!string.IsNullOrWhiteSpace(diagnostics.VmPermissionError))
            {
                report.AppendLine($"  - erreur : {Redact(diagnostics.VmPermissionError)}");
            }
            report.AppendLine($"- listage des GPU partitionnables : {YesNo(diagnostics.CanListPartitionableGpus)}");
            if (!string.IsNullOrWhiteSpace(diagnostics.GpuPermissionError))
            {
                report.AppendLine($"  - erreur : {Redact(diagnostics.GpuPermissionError)}");
            }
            report.AppendLine($"- SPLYT lance en administrateur : {YesNo(diagnostics.IsElevated)}");
        }
        report.AppendLine();

        report.AppendLine("**Machines virtuelles**");
        if (vms.Count == 0)
        {
            report.AppendLine("- aucune VM");
        }
        else
        {
            foreach (var vm in vms)
            {
                var gpuPart = string.IsNullOrWhiteSpace(vm.GpuName) ? "aucun" : $"{vm.GpuName} ({vm.GpuVramMb} Mo)";
                report.AppendLine($"- {vm.Name} : {vm.State}, {vm.Cpu} vCPU, {vm.MemoryGb} Go" +
                                  $"{(vm.DynamicMemoryEnabled ? " (memoire dynamique)" : "")}, disque {vm.DiskSizeGb} Go");
                report.AppendLine($"  - GPU-P : {gpuPart} - Windows installe : {YesNo(vm.OsInstalled)}" +
                                  $"{(string.IsNullOrWhiteSpace(vm.IsoPath) ? "" : " - ISO montee")}");
                if (!string.IsNullOrWhiteSpace(vm.LastError))
                {
                    report.AppendLine($"  - derniere erreur : {Redact(vm.LastError)}");
                }
            }
        }

        var alerts = recentAlerts.ToList();
        if (alerts.Count > 0)
        {
            report.AppendLine();
            report.AppendLine("**Dernieres erreurs du journal**");
            foreach (var alert in alerts)
            {
                report.AppendLine($"- [{alert.Source}] {Redact(alert.Message)}");
                if (!string.IsNullOrWhiteSpace(alert.Details))
                {
                    report.AppendLine($"  - {Redact(Shorten(alert.Details))}");
                }
            }
        }

        return report.ToString().TrimEnd();
    }

    /// <summary>Masque le nom de profil Windows dans les chemins : ce texte est
    /// destine a etre colle publiquement, et un chemin comme
    /// "C:\Users\Prenom.Nom\Downloads\..." identifie son auteur.
    ///
    /// Deux passes plutot qu'un motif unique, parce qu'un nom de profil Windows
    /// PEUT contenir des espaces ("C:\Users\Jean Pierre\...") : la premiere passe
    /// s'arrete au backslash suivant et couvre donc ce cas, la seconde rattrape un
    /// chemin qui finit sur le nom lui-meme, sans backslash final.</summary>
    private static string Redact(string text)
    {
        var redacted = Regex.Replace(text, @"(?i)([A-Z]:\\Users\\)[^\\\r\n]+?(?=\\)", "$1<utilisateur>");
        return Regex.Replace(redacted, @"(?i)([A-Z]:\\Users\\)[^\\\s""'\r\n]+", "$1<utilisateur>");
    }

    /// <summary>Une trace d'erreur PowerShell complete peut faire des dizaines de
    /// lignes : on garde de quoi identifier la panne sans noyer le rapport.</summary>
    private static string Shorten(string text)
    {
        var single = text.Replace("\r", " ").Replace("\n", " ").Trim();
        return single.Length <= 300 ? single : single[..300] + "...";
    }

    private static string Or(string? value) => string.IsNullOrWhiteSpace(value) ? "inconnu" : value.Trim();
    private static string YesNo(bool value) => value ? "oui" : "non";
}
