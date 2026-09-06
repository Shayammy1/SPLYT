#include "Hypervisor.hpp"
#include "WhpError.hpp"

#include <windows.h>
#include <WinHvPlatform.h>

#include <stdexcept>

namespace novavm {

bool Hypervisor::IsPresent() {
    WHV_CAPABILITY capability{};
    UINT32 written = 0;

    HRESULT hr = WHvGetCapability(
        WHvCapabilityCodeHypervisorPresent, &capability, sizeof(capability), &written);
    ThrowIfFailed(hr, "WHvGetCapability(HypervisorPresent)");

    return capability.HypervisorPresent != FALSE;
}

void Hypervisor::EnsureAvailable() {
    if (!IsPresent()) {
        throw std::runtime_error(
            "Windows Hypervisor Platform n'est pas disponible sur ce systeme. "
            "Verifiez que la virtualisation materielle est activee dans le BIOS/UEFI "
            "et que la fonctionnalite Windows \"Plateforme Hyperviseur Windows\" "
            "(HypervisorPlatform) est activee.");
    }
}

} // namespace novavm
