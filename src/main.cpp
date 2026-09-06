#include "Hypervisor.hpp"
#include "VirtualMachine.hpp"
#include "WhpError.hpp"

#include <windows.h>
#include <WinHvPlatform.h>

#include <cstdint>
#include <iostream>
#include <vector>

namespace {

constexpr WHV_GUEST_PHYSICAL_ADDRESS kGuestMemoryBase = 0x0000;
constexpr SIZE_T kGuestMemorySize = 0x1000; // 4 KiB, une page
constexpr UINT64 kCodeAddress = 0x0000;
constexpr UINT64 kStackAddress = 0x0000; // non utilisee (le programme de test ne touche pas a la pile)

// mov ax, 0x1234 ; add ax, 1 ; hlt
const std::vector<uint8_t> kTestProgram = {
    0xB8, 0x34, 0x12,
    0x83, 0xC0, 0x01,
    0xF4,
};

void PrintHeader() {
    std::cout << "================================================\n";
    std::cout << "   NovaVM - Prototype hyperviseur (WHP)\n";
    std::cout << "================================================\n\n";
}

} // namespace

int main() {
    PrintHeader();

    try {
        std::cout << "[1/7] Verification de la disponibilite de WHP...\n";
        novavm::Hypervisor::EnsureAvailable();
        std::cout << "      -> WHP est disponible sur ce systeme.\n\n";

        novavm::VirtualMachine vm;

        std::cout << "[2/7] Creation de la partition WHP...\n";
        vm.CreatePartition();
        vm.SetProcessorCount(1);
        vm.SetupPartition();
        std::cout << "      -> Partition creee et configuree (1 vCPU).\n\n";

        std::cout << "[3/7] Creation du processeur virtuel...\n";
        vm.CreateVirtualProcessor(0);
        std::cout << "      -> vCPU 0 cree.\n\n";

        std::cout << "[4/7] Allocation et mapping de la memoire invite...\n";
        vm.AllocateGuestMemory(kGuestMemorySize, kGuestMemoryBase);
        std::cout << "      -> " << kGuestMemorySize << " octets mappes a l'adresse physique "
                  << "invite 0x" << std::hex << kGuestMemoryBase << std::dec << ".\n\n";

        std::cout << "[5/7] Chargement du code de test et execution...\n";
        vm.LoadCode(kTestProgram, kCodeAddress);
        vm.SetInitialRegisters(kCodeAddress, kStackAddress);
        std::cout << "      Code : mov ax,0x1234 ; add ax,1 ; hlt\n";

        bool halted = false;
        for (int iteration = 0; iteration < 10 && !halted; ++iteration) {
            WHV_RUN_VP_EXIT_CONTEXT vpExit = vm.Run();
            switch (vpExit.ExitReason) {
                case WHvRunVpExitReasonX64Halt:
                    std::cout << "      -> vCPU arretee proprement (HLT recu).\n\n";
                    halted = true;
                    break;
                case WHvRunVpExitReasonMemoryAccess:
                    std::cerr << "      -> Erreur : acces memoire non mappee a l'adresse GPA 0x"
                              << std::hex << vpExit.MemoryAccess.Gpa << std::dec << ".\n";
                    return 1;
                default:
                    std::cerr << "      -> Sortie de vCPU inattendue (raison = "
                              << static_cast<int>(vpExit.ExitReason) << ").\n";
                    return 1;
            }
        }

        if (!halted) {
            std::cerr << "      -> Erreur : la vCPU ne s'est jamais arretee.\n";
            return 1;
        }

        std::cout << "[6/7] Verification du resultat...\n";
        const UINT64 rax = vm.ReadRegister64(WHvX64RegisterRax);
        const UINT16 ax = static_cast<UINT16>(rax & 0xFFFF);
        std::cout << "      AX = 0x" << std::hex << ax << std::dec;
        if (ax == 0x1235) {
            std::cout << "  (attendu : 0x1235) -> OK\n\n";
        } else {
            std::cout << "  (attendu : 0x1235) -> ECHEC\n\n";
            return 1;
        }

        std::cout << "[7/7] Liberation des ressources...\n";
        vm.Cleanup();
        std::cout << "      -> vCPU, memoire et partition liberees.\n\n";

        std::cout << "Prototype execute avec succes.\n";
        return 0;

    } catch (const std::exception& ex) {
        std::cerr << "\nErreur fatale : " << ex.what() << "\n";
        return 1;
    }
}
