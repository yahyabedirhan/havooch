import Testing
@testable import VRCommand
import VRWire

@Suite struct RegionArgumentTests {
    @Test(arguments: [
        ("0.48,0.30,0.28,0.12", WireRegion(x: 0.48, y: 0.3, w: 0.28, h: 0.12)),
        ("0,0,1,1", WireRegion(x: 0, y: 0, w: 1, h: 1)),
        (".1,.2,.3,.4", WireRegion(x: 0.1, y: 0.2, w: 0.3, h: 0.4)),
        // Four numbers that are no region of the frame still parse: the app refuses them, in its own words.
        ("0.9,0.9,0.3,0.3", WireRegion(x: 0.9, y: 0.9, w: 0.3, h: 0.3)),
        ("-0.1,0,0.5,0.5", WireRegion(x: -0.1, y: 0, w: 0.5, h: 0.5)),
        ("48,30,28,12", WireRegion(x: 48, y: 30, w: 28, h: 12)),
    ])
    func fourNumbersReadAsARegion(text: String, region: WireRegion) {
        #expect(RegionArgument.region(text) == region)
    }

    @Test(arguments: [
        "", "0.1,0.2,0.3", "0.1,0.2,0.3,0.4,0.5", "0.1,0.2,,0.4", "a,b,c,d", "0.1 0.2 0.3 0.4", "0.1, 0.2, 0.3, 0.4",
        "0.1,0.2,0.3,1e-1", "nan,0,1,1", "0,0,inf,1", "0,0,1,0x1", "0,0,1,+1", "0,0,1,--1", "0,0,1,1.2.3", "0,0,1,.", "0,0,1,-",
    ])
    func whatIsNotFourNumbersIsRefused(text: String) {
        #expect(RegionArgument.region(text) == nil)
    }
}
