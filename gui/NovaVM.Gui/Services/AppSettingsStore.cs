using System.IO;
using System.Text.Json;

namespace NovaVM.Gui.Services;

/// <summary>Contenu du fichier de preferences persiste (C:\NovaVM\settings.json).
/// Un seul fichier partage par plusieurs fonctionnalites (langue, etat de
/// l'activation Hyper-V...) : toujours passer par AppSettingsStore.Load/Save
/// (lecture-fusion-ecriture), jamais reecrire ce fichier a la main avec un seul
/// champ, sous peine d'effacer silencieusement les autres reglages deja enregistres.</summary>
public sealed class PersistedAppSettings
{
    /// <summary>null tant que l'utilisateur n'a jamais choisi de langue : c'est ce
    /// qui declenche le choix de langue au tout premier demarrage (voir
    /// MainViewModel.RunFirstRunFlowAsync). Une fois choisie - meme si c'est la
    /// langue par defaut - la valeur est ecrite et l'invite ne revient plus.</summary>
    public string? Language { get; set; }

    /// <summary>Vrai une fois que l'utilisateur a coche "Ne plus afficher" sur
    /// l'explication de l'onglet GPU-P.</summary>
    public bool GpuInfoDismissed { get; set; }

    /// <summary>Vrai entre le moment ou Enable-NovaVmHyperV.ps1 a active la
    /// fonctionnalite Windows Hyper-V avec succes et le redemarrage complet du PC
    /// qui finalise reellement l'activation. Sans ce drapeau, SPLYT re-proposerait
    /// exactement la meme invite "Activer Hyper-V" a chaque redemarrage de l'appli
    /// tant que le PC n'a pas redemarre (hyperVModuleInstalled reste faux jusque
    /// la) - ce qui donne l'impression trompeuse que rien ne s'est passe.</summary>
    public bool HyperVRebootPending { get; set; }
}

public static class AppSettingsStore
{
    private static readonly string FilePath = Path.Combine(@"C:\NovaVM", "settings.json");

    public static PersistedAppSettings Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return new PersistedAppSettings();
            var json = File.ReadAllText(FilePath);
            return JsonSerializer.Deserialize<PersistedAppSettings>(json) ?? new PersistedAppSettings();
        }
        catch
        {
            // Fichier corrompu/illisible : on repart de reglages par defaut plutot
            // que de faire planter le demarrage de l'appli pour ca.
            return new PersistedAppSettings();
        }
    }

    public static void Save(PersistedAppSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(settings));
        }
        catch
        {
            // Best-effort : une preference non enregistree n'est jamais une
            // raison de faire planter l'action en cours.
        }
    }
}
