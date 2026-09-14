using System.Linq;

namespace NovaVM.Gui.Models;

public sealed class HostGpu
{
    public required string Name { get; init; }
    public long VramBytes { get; init; }
    public string? DriverVersion { get; init; }
    /// <summary>GPU integre au processeur (bus PCI 0) plutot que carte dediee.
    /// Partitionner l'iGPU d'une machine qui a aussi une carte donne une VM sans
    /// puissance graphique - c'est exactement ce qui est arrive a un utilisateur
    /// avec un 9900X3D et une RTX 5080.</summary>
    public bool Integrated { get; init; }

    public bool PartitionSupported { get; init; }
    public string? PartitionCheckError { get; init; }
    public List<string> AssignedVmNames { get; init; } = new();

    public double VramGb => Math.Round(VramBytes / 1024.0 / 1024.0 / 1024.0, 1);

    /// <summary>Le meilleur GPU a partitionner d'abord : une carte dediee avant un
    /// GPU integre, et a egalite le plus de memoire. Prendre "le premier de la
    /// liste" tombait sur l'iGPU du processeur, qui est enumere en premier.</summary>
    public static HostGpu? PickBest(IEnumerable<HostGpu> gpus) => gpus
        .Where(g => g.PartitionSupported)
        .OrderBy(g => g.Integrated)
        .ThenByDescending(g => g.VramBytes)
        .FirstOrDefault();

}
