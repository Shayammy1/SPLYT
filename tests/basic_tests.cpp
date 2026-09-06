#include "Hypervisor.hpp"
#include "VirtualMachine.hpp"
#include "WhpError.hpp"

#include <windows.h>
#include <WinHvPlatform.h>

#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

// Tests de base, sans framework externe (aucun n'est requis par le projet).
// Les tests qui necessitent que WHP soit reellement utilisable sur la
// machine (fonctionnalite activee, virtualisation materielle presente)
// sont ignores proprement (SKIP) plutot que de faire echouer la suite.

namespace {

int g_passed = 0;
int g_failed = 0;
int g_skipped = 0;

void Check(bool condition, const std::string& name) {
    if (condition) {
        std::cout << "[PASS] " << name << "\n";
        ++g_passed;
    } else {
        std::cout << "[FAIL] " << name << "\n";
        ++g_failed;
    }
}

void Skip(const std::string& name, const std::string& reason) {
    std::cout << "[SKIP] " << name << " (" << reason << ")\n";
    ++g_skipped;
}

void TestFormatHResultNotEmpty() {
    const std::string message = novavm::FormatHResult(E_INVALIDARG);
    Check(!message.empty(), "FormatHResult retourne un message non vide");
}

void TestThrowIfFailedBehavior() {
    bool threwOnFailure = false;
    try {
        novavm::ThrowIfFailed(E_FAIL, "operation de test");
    } catch (const novavm::WhpException&) {
        threwOnFailure = true;
    }
    Check(threwOnFailure, "ThrowIfFailed leve une exception sur un HRESULT en echec");

    bool threwOnSuccess = false;
    try {
        novavm::ThrowIfFailed(S_OK, "operation de test");
    } catch (...) {
        threwOnSuccess = true;
    }
    Check(!threwOnSuccess, "ThrowIfFailed ne leve rien sur un HRESULT de succes");
}

void TestHypervisorPresentQuery() {
    try {
        const bool present = novavm::Hypervisor::IsPresent();
        std::cout << "       (WHvGetCapability a repondu : present=" << (present ? "true" : "false") << ")\n";
        Check(true, "Hypervisor::IsPresent() repond sans exception");
    } catch (const std::exception& ex) {
        Check(false, std::string("Hypervisor::IsPresent() repond sans exception - ") + ex.what());
    }
}

void TestFullVirtualMachineLifecycle() {
    const std::string name = "Cycle de vie complet d'une VirtualMachine (creation, execution, nettoyage)";

    bool present = false;
    try {
        present = novavm::Hypervisor::IsPresent();
    } catch (...) {
        present = false;
    }

    if (!present) {
        Skip(name, "WHP indisponible sur cette machine (fonctionnalite non activee ?)");
        return;
    }

    try {
        novavm::VirtualMachine vm;
        vm.CreatePartition();
        vm.SetProcessorCount(1);
        vm.SetupPartition();
        vm.CreateVirtualProcessor(0);
        vm.AllocateGuestMemory(0x1000, 0);

        const std::vector<uint8_t> program = {
            0xB8, 0x34, 0x12,
            0x83, 0xC0, 0x01,
            0xF4,
        };
        vm.LoadCode(program, 0);
        vm.SetInitialRegisters(0, 0);

        bool halted = false;
        for (int i = 0; i < 10 && !halted; ++i) {
            WHV_RUN_VP_EXIT_CONTEXT vpExit = vm.Run();
            if (vpExit.ExitReason == WHvRunVpExitReasonX64Halt) {
                halted = true;
            } else {
                Check(false, name + " - sortie de vCPU inattendue");
                vm.Cleanup();
                return;
            }
        }

        const UINT64 rax = vm.ReadRegister64(WHvX64RegisterRax);
        vm.Cleanup();

        Check(halted && (rax & 0xFFFF) == 0x1235, name);
    } catch (const std::exception& ex) {
        Check(false, name + " - exception : " + ex.what());
    }
}

} // namespace

int main() {
    std::cout << "=== NovaVM - Tests de base ===\n\n";

    TestFormatHResultNotEmpty();
    TestThrowIfFailedBehavior();
    TestHypervisorPresentQuery();
    TestFullVirtualMachineLifecycle();

    std::cout << "\n" << g_passed << " reussi(s), " << g_failed << " echoue(s), "
              << g_skipped << " ignore(s).\n";

    return g_failed == 0 ? 0 : 1;
}
