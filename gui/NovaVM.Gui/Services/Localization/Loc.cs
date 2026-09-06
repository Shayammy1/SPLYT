using System.IO;
using System.Text.Json;

namespace NovaVM.Gui.Services.Localization;

public enum AppLanguage
{
    French,
    English,
}

/// <summary>
/// Service de traduction minimal, sans resx/LocBaml (pas de conteneur DI ni d'etape
/// de build dans ce projet - voir App.xaml.cs). Deux dictionnaires statiques cle->texte
/// (voir Strings.cs), un fichier de preference persiste sur disque, et une
/// MarkupExtension (Markup/TrExtension.cs) pour le XAML.
///
/// Changement de langue applique au PROCHAIN demarrage de SPLYT (pas en direct) :
/// {ext:Tr Cle} resout sa valeur UNE SEULE FOIS, au chargement de chaque vue - un
/// choix delibere qui evite d'avoir a re-implementer un binding reactif (indexeur +
/// INotifyPropertyChanged) pour ~250 chaines, pour un gain (bascule instantanee)
/// que l'utilisateur a explicitement juge non necessaire.
/// </summary>
public static class Loc
{
    private static readonly string SettingsFilePath = Path.Combine(@"C:\NovaVM", "settings.json");

    public static AppLanguage CurrentLanguage { get; private set; } = LoadSavedLanguage();

    /// <summary>Traduit une cle vers le texte de la langue active. Retourne la cle
    /// elle-meme (entre crochets) si absente des deux dictionnaires, pour reperer
    /// immediatement une cle oubliee plutot que de planter ou d'afficher un vide.</summary>
    public static string Get(string key)
    {
        var table = CurrentLanguage == AppLanguage.French ? Strings.French : Strings.English;
        if (table.TryGetValue(key, out var value)) return value;
        return Strings.French.TryGetValue(key, out var fallback) ? fallback : $"[{key}]";
    }

    /// <summary>Comme Get, avec des arguments passes a string.Format sur le modele
    /// trouve (ex. "Supprimer '{0}' ?").</summary>
    public static string Get(string key, params object?[] args) => string.Format(Get(key), args);

    public static void SetLanguage(AppLanguage language)
    {
        CurrentLanguage = language;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsFilePath)!);
            File.WriteAllText(SettingsFilePath, JsonSerializer.Serialize(new PersistedSettings { Language = language.ToString() }));
        }
        catch
        {
            // Best-effort : la preference retombera sur le francais au prochain
            // demarrage si l'ecriture echoue (dossier protege, disque plein...),
            // pas une raison de faire planter le changement de langue en cours.
        }
    }

    private static AppLanguage LoadSavedLanguage()
    {
        try
        {
            if (!File.Exists(SettingsFilePath)) return AppLanguage.French;
            var json = File.ReadAllText(SettingsFilePath);
            var settings = JsonSerializer.Deserialize<PersistedSettings>(json);
            if (settings?.Language is not null && Enum.TryParse<AppLanguage>(settings.Language, out var parsed))
            {
                return parsed;
            }
        }
        catch
        {
            // Fichier corrompu/illisible : on retombe sur le francais par defaut.
        }
        return AppLanguage.French;
    }

    private sealed class PersistedSettings
    {
        public string? Language { get; set; }
    }
}
