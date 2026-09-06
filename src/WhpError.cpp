#include "WhpError.hpp"

#include <iomanip>
#include <sstream>

namespace novavm {

std::string FormatHResult(HRESULT hr) {
    char* messageBuffer = nullptr;
    DWORD size = FormatMessageA(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr,
        static_cast<DWORD>(hr),
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        reinterpret_cast<LPSTR>(&messageBuffer),
        0,
        nullptr);

    std::ostringstream oss;
    oss << "0x" << std::hex << std::uppercase << std::setfill('0') << std::setw(8)
        << static_cast<unsigned long>(hr);

    if (size > 0 && messageBuffer != nullptr) {
        std::string msg(messageBuffer, size);
        while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
            msg.pop_back();
        }
        oss << " - " << msg;
    }

    if (messageBuffer != nullptr) {
        LocalFree(messageBuffer);
    }

    return oss.str();
}

WhpException::WhpException(HRESULT hr, const std::string& operation)
    : std::runtime_error(operation + " a echoue : " + FormatHResult(hr)), hr_(hr) {}

void ThrowIfFailed(HRESULT hr, const std::string& operation) {
    if (FAILED(hr)) {
        throw WhpException(hr, operation);
    }
}

} // namespace novavm
