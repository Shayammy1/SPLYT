#pragma once

#include <windows.h>
#include <WinHvPlatform.h>

#include <cstdint>
#include <vector>

namespace novavm {

// Represente une machine virtuelle WHP unique : une partition, un vCPU et
// une region de memoire invite. Gere le cycle de vie complet (RAII) : les
// ressources sont liberees automatiquement dans le destructeur, meme en cas
// d'exception.
class VirtualMachine {
public:
    VirtualMachine();
    ~VirtualMachine();

    VirtualMachine(const VirtualMachine&) = delete;
    VirtualMachine& operator=(const VirtualMachine&) = delete;

    // Etapes de mise en place (a appeler dans cet ordre).
    void CreatePartition();
    void SetProcessorCount(UINT32 count);
    void SetupPartition();
    void CreateVirtualProcessor(UINT32 vpIndex = 0);

    // Alloue de la memoire hote (VirtualAlloc) et la mappe dans l'espace
    // physique invite a l'adresse guestBase.
    void AllocateGuestMemory(SIZE_T sizeBytes, WHV_GUEST_PHYSICAL_ADDRESS guestBase = 0);

    // Copie `code` dans la memoire invite deja mappee, a l'adresse guestAddress.
    void LoadCode(const std::vector<uint8_t>& code, WHV_GUEST_PHYSICAL_ADDRESS guestAddress);

    // Initialise CS (base=0, mode reel plat), RIP, RSP et RFLAGS.
    void SetInitialRegisters(UINT64 rip, UINT64 rsp);

    // Execute le vCPU jusqu'a la prochaine sortie (VM-exit) et la retourne.
    WHV_RUN_VP_EXIT_CONTEXT Run();

    // Lit un registre 64 bits du vCPU (ex: WHvX64RegisterRax).
    UINT64 ReadRegister64(WHV_REGISTER_NAME name) const;

    // Libere explicitement toutes les ressources. Sans effet si deja appelee.
    // Appelee automatiquement par le destructeur.
    void Cleanup() noexcept;

private:
    WHV_PARTITION_HANDLE partition_;
    UINT32 vpIndex_;
    bool vpCreated_;

    void* guestMemoryHost_;
    SIZE_T guestMemorySize_;
    WHV_GUEST_PHYSICAL_ADDRESS guestMemoryBase_;
    bool memoryMapped_;
};

} // namespace novavm
