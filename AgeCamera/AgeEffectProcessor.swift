import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum AgeEffectProcessor {
    private static let context = CIContext(options: [.cacheIntermediates: true])

    static func detectFaces(in image: CIImage) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            return request.results?.map(\.boundingBox) ?? []
        } catch {
            return []
        }
    }

    static func apply(to input: CIImage, faces: [CGRect], adjustment: Double) -> CIImage {
        guard !faces.isEmpty, abs(adjustment) > 0.5 else { return input }

        let amount = min(abs(adjustment) / 50.0, 1.0)
        let effected = adjustment < 0
            ? youngerImage(from: input, amount: amount)
            : olderImage(from: input, amount: amount)

        var result = input
        for normalizedFace in faces {
            let faceRect = imageRect(from: normalizedFace, extent: input.extent)
            let expanded = faceRect
                .insetBy(dx: -faceRect.width * 0.16, dy: -faceRect.height * 0.12)
                .intersection(input.extent)
            let mask = softOvalMask(in: expanded, canvas: input.extent)

            let blend = CIFilter.blendWithMask()
            blend.inputImage = effected
            blend.backgroundImage = result
            blend.maskImage = mask
            result = blend.outputImage?.cropped(to: input.extent) ?? result
        }

        return result
    }

    static func previewWithFaceFrames(_ input: CIImage, faces: [CGRect]) -> CIImage {
        var result = input
        let lineWidth = max(3.0, input.extent.width / 320.0)
        let color = CIColor(red: 0.25, green: 1.0, blue: 0.67, alpha: 0.95)

        for face in faces {
            let rect = imageRect(from: face, extent: input.extent)
            let top = CGRect(x: rect.minX, y: rect.maxY - lineWidth, width: rect.width, height: lineWidth)
            let bottom = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineWidth)
            let left = CGRect(x: rect.minX, y: rect.minY, width: lineWidth, height: rect.height)
            let right = CGRect(x: rect.maxX - lineWidth, y: rect.minY, width: lineWidth, height: rect.height)

            for edge in [top, bottom, left, right] {
                let border = CIImage(color: color).cropped(to: edge)
                result = border.composited(over: result)
            }
        }

        return result.cropped(to: input.extent)
    }

    static func nsImage(from image: CIImage) -> NSImage? {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: image.extent.width, height: image.extent.height))
    }

    private static func youngerImage(from input: CIImage, amount: Double) -> CIImage {
        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = input
        noiseReduction.noiseLevel = Float(0.03 + 0.07 * amount)
        noiseReduction.sharpness = Float(0.45 - 0.18 * amount)

        let softened = noiseReduction.outputImage ?? input
        let controls = CIFilter.colorControls()
        controls.inputImage = softened
        controls.saturation = Float(1.0 + 0.08 * amount)
        controls.brightness = Float(0.018 * amount)
        controls.contrast = Float(1.0 - 0.08 * amount)

        let highlights = CIFilter.highlightShadowAdjust()
        highlights.inputImage = controls.outputImage ?? softened
        highlights.shadowAmount = Float(0.15 * amount)
        highlights.highlightAmount = Float(1.0 - 0.15 * amount)
        return (highlights.outputImage ?? softened).cropped(to: input.extent)
    }

    private static func olderImage(from input: CIImage, amount: Double) -> CIImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.saturation = Float(1.0 - 0.32 * amount)
        controls.brightness = Float(-0.025 * amount)
        controls.contrast = Float(1.0 + 0.2 * amount)

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = controls.outputImage ?? input
        sharpen.sharpness = Float(0.25 + 0.9 * amount)

        let sepia = CIFilter.sepiaTone()
        sepia.inputImage = sharpen.outputImage ?? input
        sepia.intensity = Float(0.12 * amount)

        guard let toned = sepia.outputImage else { return input }

        let noise = CIFilter.randomGenerator().outputImage?.cropped(to: input.extent) ?? input
        let noiseOpacity = CIFilter.colorMatrix()
        noiseOpacity.inputImage = noise
        noiseOpacity.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(0.035 * amount))

        let overlay = CIFilter.softLightBlendMode()
        overlay.inputImage = noiseOpacity.outputImage
        overlay.backgroundImage = toned
        return (overlay.outputImage ?? toned).cropped(to: input.extent)
    }

    private static func softOvalMask(in rect: CGRect, canvas: CGRect) -> CIImage {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height) * 0.58

        let radial = CIFilter.radialGradient()
        radial.center = center
        radial.radius0 = Float(radius * 0.58)
        radial.radius1 = Float(radius)
        radial.color0 = CIColor.white
        radial.color1 = CIColor.clear

        guard let circle = radial.outputImage else {
            return CIImage(color: .white).cropped(to: rect)
        }

        let scaleX = rect.width / (radius * 2)
        let scaleY = rect.height / (radius * 2)
        let transformed = circle
            .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y))
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .transformed(by: CGAffineTransform(translationX: center.x, y: center.y))

        return transformed.cropped(to: canvas)
    }

    private static func imageRect(from normalized: CGRect, extent: CGRect) -> CGRect {
        CGRect(
            x: extent.minX + normalized.minX * extent.width,
            y: extent.minY + normalized.minY * extent.height,
            width: normalized.width * extent.width,
            height: normalized.height * extent.height
        )
    }
}
