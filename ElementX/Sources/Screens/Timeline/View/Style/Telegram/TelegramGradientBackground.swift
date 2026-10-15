//
// Copyright 2013-2026 Telegram FZ-LLC and the Telegram-iOS contributors (https://github.com/TelegramMessenger/Telegram-iOS).
// Copyright 2026 Maximilian Gaedig (UIKit port).
//
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from Telegram-iOS at commit 6ad963e, which is licensed GPL-2.0-or-later (https://telegram.org/apps):
// - submodules/GradientBackground/Sources/SoftwareGradientBackground.swift (`generateGradient`, `GradientBackgroundNode`:
//   the 8 base positions, the phase shift, the 80 x 80 render, the keyframed `contents` animation on an event);
// - submodules/Display/Source/Spring.swift (`bezierPoint`, for the custom transition curve).
// The AsyncDisplayKit node is a UIView here; clone nodes, the shared-phase signal pipe and the backwards/extended
// animations Telegram uses elsewhere are left out. The shared phase is kept so every chat continues where the last
// one left off, as Telegram's chat background does (`useSharedAnimationPhase: true`).
//

import UIKit

// MARK: - Spring.swift

private func bezierA(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat { 1.0 - 3.0 * a2 + 3.0 * a1 }
private func bezierB(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat { 3.0 * a2 - 6.0 * a1 }
private func bezierC(_ a1: CGFloat) -> CGFloat { 3.0 * a1 }

private func calcBezier(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    ((bezierA(a1, a2) * t + bezierB(a1, a2)) * t + bezierC(a1)) * t
}

private func calcSlope(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    3.0 * bezierA(a1, a2) * t * t + 2.0 * bezierB(a1, a2) * t + bezierC(a1)
}

private func getTForX(_ x: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> CGFloat {
    var t = x
    var i = 0
    while i < 4 {
        let currentSlope = calcSlope(t, x1, x2)
        if currentSlope == 0.0 {
            return t
        } else {
            let currentX = calcBezier(t, x1, x2) - x
            t -= currentX / currentSlope
        }
        i += 1
    }
    return t
}

func telegramBezierPoint(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    var value = calcBezier(getTForX(x, x1, x2), y1, y2)
    if value >= 0.997 {
        value = 1.0
    }
    return value
}

// MARK: - SoftwareGradientBackground.swift

private func shiftArray(array: [CGPoint], offset: Int) -> [CGPoint] {
    var newArray = array
    var offset = offset
    while offset > 0 {
        let element = newArray.removeFirst()
        newArray.append(element)
        offset -= 1
    }
    return newArray
}

private func gatherPositions(_ list: [CGPoint]) -> [CGPoint] {
    var result: [CGPoint] = []
    for i in 0 ..< list.count / 2 {
        result.append(list[i * 2])
    }
    return result
}

private func interpolateFloat(_ value1: CGFloat, _ value2: CGFloat, at factor: CGFloat) -> CGFloat {
    value1 * (1.0 - factor) + value2 * factor
}

private func interpolatePoints(_ point1: CGPoint, _ point2: CGPoint, at factor: CGFloat) -> CGPoint {
    CGPoint(x: interpolateFloat(point1.x, point2.x, at: factor), y: interpolateFloat(point1.y, point2.y, at: factor))
}

/// `generateGradient`: the four colours weighted by max(0, 0.92 − distance)³ around swirled positions, at 1x into a
/// BGRA bitmap (Telegram's `DrawingContext` layout).
private func generateGradient(size: CGSize, colors inputColors: [UIColor], positions: [CGPoint]) -> CGImage? {
    let colors: [UIColor] = inputColors.count == 1 ? [inputColors[0], inputColors[0], inputColors[0]] : inputColors

    let width = Int(size.width)
    let height = Int(size.height)
    guard width > 0, height > 0 else { return nil }

    var rgb = [Float](repeating: 0, count: colors.count * 3)
    for i in 0 ..< colors.count {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        colors[i].getRed(&r, green: &g, blue: &b, alpha: nil)
        rgb[i * 3 + 0] = Float(r)
        rgb[i * 3 + 1] = Float(g)
        rgb[i * 3 + 2] = Float(b)
    }

    var positionFloats = [Float](repeating: 0, count: positions.count * 2)
    for i in 0 ..< positions.count {
        positionFloats[i * 2 + 0] = Float(positions[i].x)
        positionFloats[i * 2 + 1] = Float(1.0 - positions[i].y)
    }

    let bytesPerRow = width * 4
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
        let data = context.data else {
        return nil
    }
    let imageBytes = data.assumingMemoryBound(to: UInt8.self)
    let contextBytesPerRow = context.bytesPerRow

    for y in 0 ..< height {
        let directPixelY = Float(y) / Float(height)
        let centerDistanceY = directPixelY - 0.5
        let centerDistanceY2 = centerDistanceY * centerDistanceY

        let lineBytes = imageBytes.advanced(by: contextBytesPerRow * y)
        for x in 0 ..< width {
            let directPixelX = Float(x) / Float(width)

            let centerDistanceX = directPixelX - 0.5
            let centerDistance = sqrt(centerDistanceX * centerDistanceX + centerDistanceY2)

            let swirlFactor = 0.35 * centerDistance
            let theta = swirlFactor * swirlFactor * 0.8 * 8.0
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            let pixelX = max(0.0, min(1.0, 0.5 + centerDistanceX * cosTheta - centerDistanceY * sinTheta))
            let pixelY = max(0.0, min(1.0, 0.5 + centerDistanceX * sinTheta + centerDistanceY * cosTheta))

            var distanceSum: Float = 0.0

            var r: Float = 0.0
            var g: Float = 0.0
            var b: Float = 0.0

            for i in 0 ..< colors.count {
                let colorX = positionFloats[i * 2 + 0]
                let colorY = positionFloats[i * 2 + 1]

                let distanceX = pixelX - colorX
                let distanceY = pixelY - colorY

                var distance = max(0.0, 0.92 - sqrt(distanceX * distanceX + distanceY * distanceY))
                distance = distance * distance * distance
                distanceSum += distance

                r += distance * rgb[i * 3 + 0]
                g += distance * rgb[i * 3 + 1]
                b += distance * rgb[i * 3 + 2]
            }

            if distanceSum < 0.00001 {
                distanceSum = 0.00001
            }

            let pixelB = min(b / distanceSum * 255.0, 255.0)
            let pixelG = min(g / distanceSum * 255.0, 255.0)
            let pixelR = min(r / distanceSum * 255.0, 255.0)

            let pixelBytes = lineBytes.advanced(by: x * 4)
            pixelBytes.advanced(by: 0).pointee = UInt8(pixelB)
            pixelBytes.advanced(by: 1).pointee = UInt8(pixelG)
            pixelBytes.advanced(by: 2).pointee = UInt8(pixelR)
            pixelBytes.advanced(by: 3).pointee = 0xFF
        }
    }

    return context.makeImage()
}

/// `GradientBackgroundNode` as a view: an 80 x 80 render of the four-colour gradient, stretched over the view, that
/// steps to the next phase with a keyframed animation on an event (a message sent).
final class TelegramGradientBackgroundView: UIView {
    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10),
        CGPoint(x: 0.60, y: 0.20),
        CGPoint(x: 0.35, y: 0.25),
        CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90),
        CGPoint(x: 0.40, y: 0.80),
        CGPoint(x: 0.65, y: 0.75),
        CGPoint(x: 0.75, y: 0.40)
    ]

    /// `GradientBackgroundNode.sharedPhase`.
    private static var sharedPhase = 0

    /// The transition `ChatMessageTransitionNodeImpl` reports for a sent message: 0.3 s on
    /// `verticalAnimationControlPoints`.
    static let eventDuration: Double = 0.3
    static let eventCurve: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.19919472913616398, 0.010644531250000006, 0.27920937042459737, 0.91025390625)

    let contentView = UIImageView()
    private var colors: [UIColor]
    private var phase: Int
    private var validPhase: Int?
    private var invalidated = false
    private var validLayout: CGSize?

    init(colors: [UIColor]) {
        self.colors = colors
        phase = Self.sharedPhase
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayout(size: bounds.size, animation: nil)
    }

    func updateColors(_ colors: [UIColor]) {
        guard colors != self.colors else { return }
        self.colors = colors
        invalidated = true
        if let size = validLayout {
            updateLayout(size: size, animation: nil)
        }
    }

    /// `animateEvent(transition:extendAnimation: false, backwards: false)`.
    func animateEvent() {
        if phase == 0 {
            phase = 7
        } else {
            phase -= 1
        }
        Self.sharedPhase = phase
        if let size = validLayout {
            updateLayout(size: size, animation: (Self.eventDuration, Self.eventCurve))
        }
    }

    private func updateLayout(size: CGSize, animation: (duration: Double, curve: (CGFloat, CGFloat, CGFloat, CGFloat))?) {
        guard size.width > 1, size.height > 1 else { return }
        let sizeUpdated = validLayout != size
        validLayout = size

        // `size.fitted(CGSize(width: 80.0, height: 80.0)).integralFloor`
        let scale = min(80.0 / size.width, 80.0 / size.height)
        let imageSize = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))

        let positions = gatherPositions(shiftArray(array: Self.basePositions, offset: phase % 8))

        if let validPhase {
            if validPhase != phase || invalidated {
                self.validPhase = phase
                invalidated = false

                let steps = [gatherPositions(shiftArray(array: Self.basePositions, offset: validPhase % 8)), positions]

                if let animation, animation.duration > 0.001 {
                    var images: [CGImage] = []
                    let stepCount = steps.count - 1
                    let fps = 30.0
                    let maxFrame = Int(animation.duration * fps)
                    let framesPerAnyStep = maxFrame / stepCount

                    for frameIndex in 0 ..< maxFrame {
                        let t = telegramBezierPoint(animation.curve.0, animation.curve.1, animation.curve.2, animation.curve.3,
                                                    CGFloat(frameIndex) / CGFloat(maxFrame - 1))
                        let globalStep = Int(t * CGFloat(maxFrame))
                        let stepIndex = min(stepCount - 1, globalStep / framesPerAnyStep)

                        let stepFrameIndex = globalStep - stepIndex * framesPerAnyStep
                        let stepFrames = stepIndex == stepCount - 1 ? maxFrame - framesPerAnyStep * (stepCount - 1) : framesPerAnyStep
                        let stepT = CGFloat(stepFrameIndex) / CGFloat(stepFrames - 1)

                        var morphedPositions: [CGPoint] = []
                        for i in 0 ..< steps[0].count {
                            morphedPositions.append(interpolatePoints(steps[stepIndex][i], steps[stepIndex + 1][i], at: stepT))
                        }
                        if let image = generateGradient(size: imageSize, colors: colors, positions: morphedPositions) {
                            images.append(image)
                        }
                    }

                    if let last = images.last {
                        contentView.image = UIImage(cgImage: last)
                        let keyframes = CAKeyframeAnimation(keyPath: "contents")
                        keyframes.values = images
                        keyframes.duration = animation.duration
                        keyframes.calculationMode = .linear
                        keyframes.isRemovedOnCompletion = true
                        contentView.layer.removeAnimation(forKey: "contents")
                        contentView.layer.add(keyframes, forKey: "contents")
                    }
                } else if let image = generateGradient(size: imageSize, colors: colors, positions: positions) {
                    contentView.image = UIImage(cgImage: image)
                }
            } else if sizeUpdated, let image = generateGradient(size: imageSize, colors: colors, positions: positions) {
                contentView.image = UIImage(cgImage: image)
                self.validPhase = phase
            }
        } else if sizeUpdated, let image = generateGradient(size: imageSize, colors: colors, positions: positions) {
            contentView.image = UIImage(cgImage: image)
            self.validPhase = phase
        }

        contentView.frame = CGRect(origin: .zero, size: size)
    }
}
