#pragma once

#include <windows.h>

#include <stdexcept>
#include <string>

namespace novavm {

// Exception levee lorsqu'un appel a l'API Windows Hypervisor Platform echoue.
class WhpException : public std::runtime_error {
public:
    WhpException(HRESULT hr, const std::string& operation);

    HRESULT Code() const noexcept { return hr_; }

private:
    HRESULT hr_;
};

// Formate un HRESULT en une chaine lisible : "0xXXXXXXXX - <message systeme>".
std::string FormatHResult(HRESULT hr);

// Leve une WhpException si hr represente un echec (FAILED(hr)).
void ThrowIfFailed(HRESULT hr, const std::string& operation);

} // namespace novavm
