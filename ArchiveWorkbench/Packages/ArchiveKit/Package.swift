// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArchiveKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ArchiveDomain", targets: ["ArchiveDomain"]),
        .library(name: "ArchiveSecurity", targets: ["ArchiveSecurity"]),
        .library(name: "ArchiveOperations", targets: ["ArchiveOperations"]),
        .library(name: "ArchiveFixtures", targets: ["ArchiveFixtures"]),
        .library(name: "CMinizipBridge", targets: ["CMinizipBridge"]),
        .library(name: "CLibArchiveBridge", targets: ["CLibArchiveBridge"]),
        .library(name: "ArchiveProviders", targets: ["ArchiveProviders"]),
    ],
    targets: [
        .target(
            name: "CMinizipBridge",
            path: "Sources/CMinizipBridge",
            sources: [
                "AWBMinizipBridge.c",
                "vendor/mz_crypt.c",
                "vendor/mz_crypt_apple.c",
                "vendor/mz_os.c",
                "vendor/mz_os_posix.c",
                "vendor/mz_strm.c",
                "vendor/mz_strm_buf.c",
                "vendor/mz_strm_libcomp.c",
                "vendor/mz_strm_mem.c",
                "vendor/mz_strm_os_posix.c",
                "vendor/mz_strm_pkcrypt.c",
                "vendor/mz_strm_split.c",
                "vendor/mz_strm_wzaes.c",
                "vendor/mz_zip.c",
                "vendor/mz_zip_rw.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_LIBCOMP"),
                .define("HAVE_WZAES"),
                .define("HAVE_PKCRYPT"),
                .define("_DARWIN_C_SOURCE"),
                .headerSearchPath("vendor"),
            ],
            linkerSettings: [.linkedLibrary("compression")]
        ),
        .systemLibrary(
            name: "CLibArchiveBridge",
            path: "Sources/CLibArchiveBridge",
            pkgConfig: "libarchive",
            providers: [
                .brew(["libarchive"]),
            ]
        ),
        .target(name: "ArchiveDomain"),
        .target(name: "ArchiveSecurity", dependencies: ["ArchiveDomain"]),
        .target(name: "ArchiveOperations", dependencies: ["ArchiveDomain"]),
        .target(name: "ArchiveFixtures", dependencies: ["ArchiveDomain"]),
        .target(
            name: "ArchiveProviders",
            dependencies: ["ArchiveDomain", "ArchiveOperations", "ArchiveSecurity", "CMinizipBridge", "CLibArchiveBridge"]
        ),
        .testTarget(name: "ArchiveDomainTests", dependencies: ["ArchiveDomain"]),
        .testTarget(name: "ArchiveSecurityTests", dependencies: ["ArchiveSecurity", "ArchiveFixtures"]),
        .testTarget(name: "ArchiveOperationsTests", dependencies: ["ArchiveOperations"]),
        .testTarget(name: "CMinizipBridgeTests", dependencies: ["CMinizipBridge"]),
        .testTarget(
            name: "ArchiveProvidersTests",
            dependencies: ["ArchiveProviders", "ArchiveDomain"]
        ),
    ]
)
