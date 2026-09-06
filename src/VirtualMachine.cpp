#include "VirtualMachine.hpp"
#include "WhpError.hpp"

#include <cstring>
#include <stdexcept>
#include <string>

namespace novavm {

VirtualMachine::VirtualMachine()
    : partition_(nullptr),
      vpIndex_(0),
      vpCreated_(false),
      guestMemoryHost_(nullptr),
      guestMemorySize_(0),
      guestMemoryBase_(0),
      memoryMapped_(false) {}

VirtualMachine::~VirtualMachine() {
    Cleanup();
}

void VirtualMachine::CreatePartition() {
    HRESULT hr = WHvCreatePartition(&partition_);
    ThrowIfFailed(hr, "WHvCreatePartition");
}

void VirtualMachine::SetProcessorCount(UINT32 count) {
    WHV_PARTITION_PROPERTY property{};
    property.ProcessorCount = count;

    HRESULT hr = WHvSetPartitionProperty(
        partition_, WHvPartitionPropertyCodeProcessorCount, &property, sizeof(property));
    ThrowIfFailed(hr, "WHvSetPartitionProperty(ProcessorCount)");
}

void VirtualMachine::SetupPartition() {
    HRESULT hr = WHvSetupPartition(partition_);
    ThrowIfFailed(hr, "WHvSetupPartition");
}

void VirtualMachine::CreateVirtualProcessor(UINT32 vpIndex) {
    HRESULT hr = WHvCreateVirtualProcessor(partition_, vpIndex, 0);
    ThrowIfFailed(hr, "WHvCreateVirtualProcessor");
    vpIndex_ = vpIndex;
    vpCreated_ = true;
}

void VirtualMachine::AllocateGuestMemory(SIZE_T sizeBytes, WHV_GUEST_PHYSICAL_ADDRESS guestBase) {
    SYSTEM_INFO sysInfo{};
    GetSystemInfo(&sysInfo);
    const SIZE_T pageSize = sysInfo.dwPageSize;
    const SIZE_T alignedSize = ((sizeBytes + pageSize - 1) / pageSize) * pageSize;

    void* memory = VirtualAlloc(nullptr, alignedSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (memory == nullptr) {
        throw std::runtime_error(
            "VirtualAlloc a echoue (memoire invite), code erreur : " + std::to_string(GetLastError()));
    }

    HRESULT hr = WHvMapGpaRange(
        partition_,
        memory,
        guestBase,
        static_cast<UINT64>(alignedSize),
        WHvMapGpaRangeFlagRead | WHvMapGpaRangeFlagWrite | WHvMapGpaRangeFlagExecute);
    if (FAILED(hr)) {
        VirtualFree(memory, 0, MEM_RELEASE);
        ThrowIfFailed(hr, "WHvMapGpaRange");
    }

    guestMemoryHost_ = memory;
    guestMemorySize_ = alignedSize;
    guestMemoryBase_ = guestBase;
    memoryMapped_ = true;
}

void VirtualMachine::LoadCode(const std::vector<uint8_t>& code, WHV_GUEST_PHYSICAL_ADDRESS guestAddress) {
    if (!memoryMapped_) {
        throw std::runtime_error("La memoire invite doit etre allouee avant de charger du code.");
    }
    if (guestAddress < guestMemoryBase_ ||
        guestAddress + code.size() > guestMemoryBase_ + guestMemorySize_) {
        throw std::runtime_error("Le code depasse la region de memoire invite mappee.");
    }

    const UINT64 offset = guestAddress - guestMemoryBase_;
    std::memcpy(static_cast<uint8_t*>(guestMemoryHost_) + offset, code.data(), code.size());
}

void VirtualMachine::SetInitialRegisters(UINT64 rip, UINT64 rsp) {
    // Segment de code plat (base=0) pour que RIP corresponde directement a
    // une adresse physique invite, en mode reel.
    WHV_X64_SEGMENT_REGISTER cs{};
    cs.Base = 0;
    cs.Limit = 0xFFFF;
    cs.Selector = 0;
    cs.SegmentType = 11; // execution/lecture
    cs.NonSystemSegment = 1;
    cs.Present = 1;
    cs.DescriptorPrivilegeLevel = 0;
    cs.Granularity = 0;
    cs.Long = 0;
    cs.Default = 0;

    constexpr UINT32 kCount = 4;
    WHV_REGISTER_NAME names[kCount] = {
        WHvX64RegisterCs,
        WHvX64RegisterRip,
        WHvX64RegisterRsp,
        WHvX64RegisterRflags,
    };
    WHV_REGISTER_VALUE values[kCount] = {};
    values[0].Segment = cs;
    values[1].Reg64 = rip;
    values[2].Reg64 = rsp;
    values[3].Reg64 = 0x2; // bit 1 reserve, doit toujours valoir 1

    HRESULT hr = WHvSetVirtualProcessorRegisters(partition_, vpIndex_, names, kCount, values);
    ThrowIfFailed(hr, "WHvSetVirtualProcessorRegisters");
}

WHV_RUN_VP_EXIT_CONTEXT VirtualMachine::Run() {
    WHV_RUN_VP_EXIT_CONTEXT exitContext{};
    HRESULT hr = WHvRunVirtualProcessor(partition_, vpIndex_, &exitContext, sizeof(exitContext));
    ThrowIfFailed(hr, "WHvRunVirtualProcessor");
    return exitContext;
}

UINT64 VirtualMachine::ReadRegister64(WHV_REGISTER_NAME name) const {
    WHV_REGISTER_VALUE value{};
    HRESULT hr = WHvGetVirtualProcessorRegisters(partition_, vpIndex_, &name, 1, &value);
    ThrowIfFailed(hr, "WHvGetVirtualProcessorRegisters");
    return value.Reg64;
}

void VirtualMachine::Cleanup() noexcept {
    if (vpCreated_) {
        WHvDeleteVirtualProcessor(partition_, vpIndex_);
        vpCreated_ = false;
    }
    if (memoryMapped_) {
        WHvUnmapGpaRange(partition_, guestMemoryBase_, static_cast<UINT64>(guestMemorySize_));
        memoryMapped_ = false;
    }
    if (guestMemoryHost_ != nullptr) {
        VirtualFree(guestMemoryHost_, 0, MEM_RELEASE);
        guestMemoryHost_ = nullptr;
    }
    if (partition_ != nullptr) {
        WHvDeletePartition(partition_);
        partition_ = nullptr;
    }
}

} // namespace novavm
