import FaroCoreFFI
import Testing

struct FaroCoreTests {
    @Test func loadsMetadataFromTheRealRustLibrary() {
        #expect(FaroCore.name == "Faro")
        #expect(FaroCore.tagline == "Your personal, open-source agent.")
        #expect(FaroCore.status.contains("Agent runtime coming next."))
        #expect(FaroCore.version == "0.1.0")
    }

    @Test func invalidFieldsAndOffsetsAreRejected() {
        #expect(faro_metadata_field(-1) == nil)
        #expect(faro_metadata_field(4) == nil)
        #expect(faro_metadata_length(4) == -1)
        #expect(faro_metadata_byte(0, -1) == -1)
        #expect(faro_metadata_byte(0, faro_metadata_length(0)) == -1)
    }
}
