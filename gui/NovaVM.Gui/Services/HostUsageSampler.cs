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
