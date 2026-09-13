using System.Diagnostics;
using System.Runtime.InteropServices;

namespace NovaVM.Gui.Services;

/// <summary>
/// Mesure l'utilisation CPU et la RAM disponible de l'hote DANS le processus, via
/// deux appels systeme Windows, sans passer par PowerShell.
///
/// Pourquoi pas Get-NovaVmHostStats.ps1 comme le reste : ce script lance un
/// processus powershell.exe et quatre requetes CIM. C'est parfait pour un
/// rafraichissement ponctuel, mais l'appeler chaque seconde couterait en
/// permanence une part notable d'un coeur - et gonflerait donc le chiffre
/// d'utilisation CPU que l'on cherche justement a afficher. Les deux appels
/// ci-dessous, eux, coutent quelques microsecondes.
/// </summary>
public sealed class HostUsageSampler
{
    private ulong _previousIdle;
    private ulong _previousBusy;
    private bool _hasBaseline;

    /// <summary>Pourcentage d'utilisation CPU depuis l'appel precedent, ou null au
    /// tout premier appel : une mesure d'utilisation est forcement un ecart entre
    /// deux instants, il n'y a rien a rapporter tant qu'il n'existe qu'un point.
    /// C'est exactement la methode du Gestionnaire des taches.</summary>
    public double? SampleCpuPercent()
    {
        if (!NativeUsage.GetSystemTimes(out var idleTime, out var kernelTime, out var userTime))
        {
            return null;
        }

        var idle = ToUInt64(idleTime);
        // Sous Windows, le temps "kernel" INCLUT le temps d'inactivite : le total
        // est donc kernel + user, et l'occupation vaut total - idle.
        var total = ToUInt64(kernelTime) + ToUInt64(userTime);
        var busy = total - idle;

        if (!_hasBaseline)
        {
            _previousIdle = idle;
            _previousBusy = busy;
            _hasBaseline = true;
            return null;
        }

        var idleDelta = idle - _previousIdle;
        var busyDelta = busy - _previousBusy;
        _previousIdle = idle;
        _previousBusy = busy;

        var totalDelta = busyDelta + idleDelta;
        if (totalDelta == 0) return null;

        var percent = (double)busyDelta / totalDelta * 100.0;
        return Math.Round(Math.Clamp(percent, 0, 100), 0);
    }

    /// <summary>RAM physique disponible en Go, ou null si la mesure echoue.</summary>
    public double? SampleAvailableRamGb()
    {
        var status = new NativeUsage.MemoryStatusEx { Length = (uint)Marshal.SizeOf<NativeUsage.MemoryStatusEx>() };
        if (!NativeUsage.GlobalMemoryStatusEx(ref status)) return null;
        return Math.Round(status.AvailablePhysical / 1024.0 / 1024.0 / 1024.0, 1);
    }

    /// <summary>Utilisation GPU de l'hote en pourcentage, ou null si Windows ne
    /// sait pas la fournir.
    ///
    /// Methode du Gestionnaire des taches : le compteur "GPU Engine" expose une
    /// occupation par MOTEUR (3D, copie, encodage video, decodage...) et par
    /// processus. Ce que l'on montre comme "le GPU", c'est le moteur le plus
    /// charge - et non la somme, qui depasserait allegrement 100 % des qu'un jeu
    /// fait travailler le rendu et l'encodage en meme temps, ce qui est
    /// precisement le cas d'une VM en streaming.
    ///
    /// Le premier appel est lent (Windows construit la liste des instances) et
    /// peut rendre null : comme pour le CPU, une mesure a besoin de deux points.
    /// </summary>
    public double? SampleGpuPercent()
    {
        if (_gpuUnavailable) return null;

        try
        {
            _gpuCategory ??= new PerformanceCounterCategory("GPU Engine");
            var best = 0.0d;
            var seen = false;

            foreach (var instance in _gpuCategory.GetInstanceNames())
            {
                // Une instance par couple processus/moteur. On agrege par moteur :
                // c'est la charge de la PUCE qui interesse, pas celle d'un
                // programme en particulier.
                if (!_gpuCounters.TryGetValue(instance, out var counter))
                {
                    counter = new PerformanceCounter("GPU Engine", "Utilization Percentage", instance, readOnly: true);
                    _gpuCounters[instance] = counter;
                    counter.NextValue();   // amorce : la premiere lecture vaut toujours 0
                    continue;
                }

                var engine = ExtractEngine(instance);
                var value = counter.NextValue();
                _gpuByEngine[engine] = _gpuByEngine.TryGetValue(engine, out var running) ? running + value : value;
                seen = true;
            }

            foreach (var total in _gpuByEngine.Values)
            {
                if (total > best) best = total;
            }
            _gpuByEngine.Clear();

            return seen ? Math.Round(Math.Clamp(best, 0, 100), 0) : null;
        }
        catch (Exception)
        {
            // Compteurs absents ou corrompus (cas connu apres certaines mises a
            // jour de pilote) : on cesse d'essayer plutot que de relancer une
            // exception chaque seconde.
            _gpuUnavailable = true;
            return null;
        }
    }

    /// <summary>"pid_1234_luid_0x..._phys_0_eng_3_engtype_3D" -> "3D".</summary>
    private static string ExtractEngine(string instanceName)
    {
        const string marker = "engtype_";
        var index = instanceName.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
        return index < 0 ? instanceName : instanceName[(index + marker.Length)..];
    }

    private PerformanceCounterCategory? _gpuCategory;
    private readonly Dictionary<string, PerformanceCounter> _gpuCounters = new();
    private readonly Dictionary<string, float> _gpuByEngine = new();
    private bool _gpuUnavailable;

    private static ulong ToUInt64(NativeUsage.FileTime time) =>
        ((ulong)time.HighDateTime << 32) | time.LowDateTime;

    private static class NativeUsage
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct FileTime
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MemoryStatusEx
        {
            public uint Length;
            public uint MemoryLoad;
            public ulong TotalPhysical;
            public ulong AvailablePhysical;
            public ulong TotalPageFile;
            public ulong AvailablePageFile;
            public ulong TotalVirtual;
            public ulong AvailableVirtual;
            public ulong AvailableExtendedVirtual;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetSystemTimes(out FileTime idleTime, out FileTime kernelTime, out FileTime userTime);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx buffer);
    }
}
