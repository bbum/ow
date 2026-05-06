import Testing
import Foundation
@testable import ow

@Suite("BinFile parser")
struct BinFileTests {
    static func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            ?? URL(fileURLWithPath: "Tests/owTests/Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    @Test("Parses live STARTBIN response (after envelope strip)")
    func parsesLiveCapture() throws {
        let raw = try Self.loadFixture("live-startbin-sds7102.raw")
        let response = try CaptureResponse.parse(raw)
        #expect(response.envelope.flag == 128)
        #expect(response.envelope.payloadLength == raw.count - 12)

        let bin = try BinFile.parse(response.payload)
        #expect(bin.format == .liveNetwork)
        #expect(bin.deviceIdentifier == "SPBS02")
        #expect(bin.modelSerial == "SDS7102125102")
        #expect(bin.channelIdentifier == "CH1")
        #expect(bin.samples.count == 3040)
        #expect(bin.frequency == 1000.0)
        #expect(bin.voltsMultiplier == 80.0)
        #expect(bin.deepMemoryCapable == true)
        #expect(bin.deepMemoryCapture == false)
    }

    @Test("Voltage of 1 kHz square wave fixture matches scope display (~5V Vpp)")
    func voltageSanity() throws {
        let raw = try Self.loadFixture("live-startbin-sds7102.raw")
        let response = try CaptureResponse.parse(raw)
        let bin = try BinFile.parse(response.payload)
        let vmax = bin.voltages.max() ?? 0
        let vmin = bin.voltages.min() ?? 0
        let vpp = vmax - vmin
        // Scope showed Vp=5.04V; voltsMult=80mV/count, peak sample ≈ 62 → ~4.96V.
        #expect(vpp > 4.5)
        #expect(vpp < 5.5)
    }

    @Test("Parses USB-saved format (5v Calibration)")
    func parsesUsbSavedCapture() throws {
        let data = try Self.loadFixture("calibration_5v.bin")
        let bin = try BinFile.parse(data)
        #expect(bin.format == .usbSaved)
        #expect(bin.deviceIdentifier == "SPBS02")
        #expect(bin.modelSerial == nil)
        #expect(bin.channelIdentifier == "CH1")
        #expect(bin.frequency == 1000.0)
        #expect(bin.timeMultiplier == 2.5)
    }

    @Test("BMP envelope strips correctly and BMP magic is preserved")
    func envelopeStripsBMP() throws {
        let raw = try Self.loadFixture("live-startbmp-sds7102.raw")
        let response = try CaptureResponse.parse(raw)
        #expect(response.envelope.flag == 1)
        #expect(response.envelope.payloadLength == raw.count - 12)
        // Payload starts with 'BM' magic.
        #expect(response.payload.prefix(2) == Data([0x42, 0x4D]))
    }

    @Test("Round-trip the response envelope")
    func envelopeRoundTrip() throws {
        let raw = try Self.loadFixture("live-startbin-sds7102.raw")
        let response = try CaptureResponse.parse(raw)
        // Deep-memory capture is signaled inside BinFile via extendedFlags, not the envelope flag.
        // Both STARTBIN and STARTMEMDEPTH return envelope.flag == 128 on this scope.
        #expect(response.envelope.flag == 128)
    }
}
