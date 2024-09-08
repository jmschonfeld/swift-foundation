
@inline(never)
func blackHole<T>(_: T) {}

// Ensure that all modules can be imported successfully
import FoundationEssentials
import FoundationInternationalization

// Ensure that FoundationMacros cannot be imported
#if canImport(FoundationMacros)
#error("FoundationMacros should not be able to be imported")
#endif

// Ensure types in each module work
blackHole(Data())
blackHole(Locale(identifier: "en_US"))

// Ensure that macros can be used
blackHole(#Predicate<Int> { $0 > 2 })
blackHole(#Expression<Int> { $0 > 2 })

print("swift-foundation FundamentalToolchainTests finished successfully")
