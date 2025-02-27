# Generated by devtools/yamaker.

LIBRARY()



LICENSE(Apache-2.0)

PEERDIR(
    contrib/restricted/abseil-cpp/absl/base
    contrib/restricted/abseil-cpp/absl/base/internal/raw_logging
    contrib/restricted/abseil-cpp/absl/base/internal/spinlock_wait
    contrib/restricted/abseil-cpp/absl/base/internal/throw_delegate
    contrib/restricted/abseil-cpp/absl/base/log_severity
    contrib/restricted/abseil-cpp/absl/city
    contrib/restricted/abseil-cpp/absl/numeric
    contrib/restricted/abseil-cpp/absl/strings
    contrib/restricted/abseil-cpp/absl/strings/internal
    contrib/restricted/abseil-cpp/absl/types/bad_optional_access
    contrib/restricted/abseil-cpp/absl/types/bad_variant_access
)

ADDINCL(
    GLOBAL contrib/restricted/abseil-cpp
)

NO_COMPILER_WARNINGS()

NO_UTIL()

CFLAGS(
    -DNOMINMAX
)

SRCS(
    internal/hash.cc
)

END()
