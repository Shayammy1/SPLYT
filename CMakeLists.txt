cmake_minimum_required(VERSION 3.20)
project(NovaVM LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "NovaVM necessite Windows (Windows Hypervisor Platform).")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(novavm_core STATIC
    src/Hypervisor.cpp
    src/VirtualMachine.cpp
    src/WhpError.cpp
)

target_include_directories(novavm_core PUBLIC include)
target_compile_definitions(novavm_core PUBLIC WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(novavm_core PUBLIC WinHvPlatform)

if(MSVC)
    target_compile_options(novavm_core PRIVATE /W4 /permissive-)
endif()

add_executable(NovaVM src/main.cpp)
target_link_libraries(NovaVM PRIVATE novavm_core)

enable_testing()
add_executable(NovaVMTests tests/basic_tests.cpp)
target_link_libraries(NovaVMTests PRIVATE novavm_core)
add_test(NAME NovaVMTests COMMAND NovaVMTests)
