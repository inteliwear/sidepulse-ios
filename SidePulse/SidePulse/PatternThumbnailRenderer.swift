// Copyright (c) 2026 InteliWEAR LLC. MPL-2.0.
import UIKit
import CryptoKit

/// Content-addressed PNG thumbnails shared by the app and App Intents. The native
/// sampler uses the same controller as the offline WASM preview, including raw DSL.
enum PatternThumbnailRenderer {
    private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.countLimit = 128
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    static func data(for pattern: LibraryPattern) -> Data? {
        let source = Data(pattern.ledText.utf8)
        let key = SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined() as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }
        var rgb = [UInt8](repeating: 0, count: 6)
        let valid = source.withUnsafeBytes { bytes in
            SidePulseThumbnailSample(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &rgb)
        }
        guard let data = render(rgb: rgb, valid: valid)?.pngData() else { return nil }
        cache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }

    private static func render(rgb: [UInt8], valid: Bool) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "dot-preview", withExtension: "png", subdirectory: "PatternPreviewWeb"),
              let base = UIImage(contentsOfFile: url.path) else { return nil }
        let size = CGSize(width: 256, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            // Same CAD image, diffuser contour and viewbox as device-preview.mjs.
            context.translateBy(x: 128, y: 128)
            context.rotate(by: -.pi / 14)
            context.scaleBy(x: 0.16, y: 0.16)
            context.translateBy(x: -900, y: -845)
            let bounds = CGRect(x: 0, y: 0, width: 1800, height: 1800)
            context.setShadow(offset: CGSize(width: 0, height: 24), blur: 40, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            base.draw(in: bounds)
            context.setShadow(offset: .zero, blur: 0, color: nil)

            let diffuser = UIBezierPath()
            diffuser.move(to: CGPoint(x: 338, y: 908))
            diffuser.addLine(to: CGPoint(x: 1461, y: 908))
            diffuser.addLine(to: CGPoint(x: 1473, y: 919))
            diffuser.addLine(to: CGPoint(x: 1473, y: 1135))
            diffuser.addQuadCurve(to: CGPoint(x: 1371, y: 1256), controlPoint: CGPoint(x: 1473, y: 1201))
            diffuser.addLine(to: CGPoint(x: 429, y: 1256))
            diffuser.addQuadCurve(to: CGPoint(x: 326, y: 1135), controlPoint: CGPoint(x: 326, y: 1200))
            diffuser.addLine(to: CGPoint(x: 326, y: 920))
            diffuser.close()
            context.saveGState()
            diffuser.addClip()
            // Neutralize the render's original colors without flattening its highlights.
            context.setBlendMode(.saturation)
            UIColor.gray.setFill()
            context.fill(bounds)
            context.setBlendMode(.normal)
            var colors: [CGColor] = []
            var locations: [CGFloat] = []
            for index in 0...32 {
                let position = Double(index) / 32 * 2
                let weights = [exp(-0.5 * pow((position - 0.5) / 0.62, 2)), exp(-0.5 * pow((position - 1.5) / 0.62, 2))]
                let channels = (0..<3).map { channel in
                    (Double(rgb[channel]) * weights[0] + Double(rgb[channel + 3]) * weights[1]) / (weights[0] + weights[1])
                }
                let peak = (channels.max() ?? 0) / 255
                let ambient = 0.32 * pow(1 - peak, 2)
                colors.append(UIColor(red: min(1, ambient + channels[0]/255),
                                      green: min(1, ambient + channels[1]/255),
                                      blue: min(1, ambient + channels[2]/255), alpha: 1).cgColor)
                locations.append(CGFloat(index) / 32)
            }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
                context.setBlendMode(.color)
                context.drawLinearGradient(gradient, start: CGPoint(x: 326, y: 0), end: CGPoint(x: 1473, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.setBlendMode(.normal)
                context.setAlpha(0.65)
                context.drawLinearGradient(gradient, start: CGPoint(x: 326, y: 0), end: CGPoint(x: 1473, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                context.setAlpha(1)
            }
            let finishColors = [UIColor.white.withAlphaComponent(0.25).cgColor, UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.16).cgColor]
            if let finish = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: finishColors as CFArray, locations: [0, 0.4, 1]) {
                context.drawLinearGradient(finish, start: CGPoint(x: 0, y: 908), end: CGPoint(x: 0, y: 1256), options: [])
            }
            context.restoreGState()
            if !valid {
                // A syntax error is represented as a source document, not a red pattern.
                let badge = UIImage(systemName: "doc.text.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 180))?
                    .withTintColor(.systemGray, renderingMode: .alwaysOriginal)
                badge?.draw(in: CGRect(x: 1210, y: 1250, width: 180, height: 210))
            }
        }
    }
}
