// Compute links libswiftDemangle for one function. Swift ships that library only as a shared
// object that itself loads libswiftCore.so, so an executable with a statically linked Swift
// runtime cannot use it, and the static Linux SDK has none at all. The cross builds link this
// instead; a complete port builds Swift's Demangling library statically.
//
// Symbolic references are described in swift/docs/ABI/Mangling.rst: a control byte
// 0x01-0x17 is followed by a 4-byte relative offset, 0x18-0x1F by a pointer.

#include <cstdint>
#include <swift/Demangling/Demangle.h>

llvm::StringRef swift::Demangle::makeSymbolicMangledNameStringRef(const char *base) {
    if (!base) {
        return {};
    }
    const char *end = base;
    while (*end != '\0') {
        if (*end >= '\x01' && *end <= '\x17') {
            end += sizeof(uint32_t);
        } else if (*end >= '\x18' && *end <= '\x1F') {
            end += sizeof(void *);
        }
        ++end;
    }
    return llvm::StringRef(base, end - base);
}
