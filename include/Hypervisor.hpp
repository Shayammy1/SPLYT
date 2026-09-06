#pragma once

namespace novavm {

// Fonctions statiques liees a la plateforme (Windows Hypervisor Platform)
// independamment de toute machine virtuelle particuliere.
class Hypervisor {
public:
    // Interroge WHvGetCapability pour savoir si un hyperviseur compatible
    // WHP est present et utilisable sur cette machine.
    static bool IsPresent();

    // Comme IsPresent(), mais leve une exception explicite si WHP n'est pas
    // disponible (message d'erreur destine a l'utilisateur final).
    static void EnsureAvailable();
};

} // namespace novavm
