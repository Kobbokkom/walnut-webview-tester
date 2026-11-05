import CoreGraphics

// Use the fold's local frame, including system margins, instead of device dimensions.
enum DevToolsWorkspaceLayout {
    static func frames(in size: CGSize, division: CGRect?) -> (browser: CGRect, tools: CGRect) {
        let bounds = CGRect(origin: .zero, size: size)
        if let division {
            let fold = division.intersection(bounds)
            if !fold.isNull, !fold.isEmpty {
                if fold.height > fold.width, fold.minX > 0, fold.maxX < size.width {
                    return (
                        CGRect(x: 0, y: 0, width: fold.minX, height: size.height),
                        CGRect(x: fold.maxX, y: 0, width: size.width - fold.maxX, height: size.height)
                    )
                }
                if fold.width >= fold.height, fold.minY > 0, fold.maxY < size.height {
                    return (
                        CGRect(x: 0, y: 0, width: size.width, height: fold.minY),
                        CGRect(x: 0, y: fold.maxY, width: size.width, height: size.height - fold.maxY)
                    )
                }
            }
        }
        let browserWidth = size.width * 0.58
        return (
            CGRect(x: 0, y: 0, width: browserWidth, height: size.height),
            CGRect(x: browserWidth, y: 0, width: size.width - browserWidth, height: size.height)
        )
    }
}
