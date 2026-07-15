import Foundation
import SwiftUI

// MARK: - Platform Detection

/// 平台检测工具
public enum PlatformUtils {
    #if os(iOS)
    public static let currentPlatform: Platform = .iOS
    #elseif os(macOS)
    public static let currentPlatform: Platform = .macOS
    #elseif os(tvOS)
    public static let currentPlatform: Platform = .tvOS
    #elseif os(visionOS)
    public static let currentPlatform: Platform = .visionOS
    #else
    public static let currentPlatform: Platform = .unknown
    #endif

    public enum Platform: String, Sendable {
        case iOS
        case macOS
        case tvOS
        case visionOS
        case unknown

        public var isPhone: Bool { self == .iOS }
        public var isPad: Bool { self == .iOS } // 在 iOS 上可能是 iPad
        public var isDesktop: Bool { self == .macOS }
        public var isTV: Bool { self == .tvOS }
        public var isVision: Bool { self == .visionOS }
    }

    /// 是否在 macOS 上运行
    public static var isMacOS: Bool { currentPlatform == .macOS }

    /// 是否在 iOS 上运行
    public static var isiOS: Bool { currentPlatform == .iOS }

    /// 是否在 tvOS 上运行
    public static var istvOS: Bool { currentPlatform == .tvOS }

    /// 是否在 visionOS 上运行
    public static var isvisionOS: Bool { currentPlatform == .visionOS }

    /// 是否为触控设备
    public static var isTouchDevice: Bool { isiOS || isvisionOS }

    /// 是否支持焦点导航
    public static var supportsFocusNavigation: Bool { istvOS || isvisionOS }
}

// MARK: - Platform-Specific View Modifiers

/// 平台自适应修饰符
public struct PlatformAdaptiveModifier<PhoneContent: View, PadContent: View, MacContent: View, TVContent: View>: ViewModifier {
    let phone: PhoneContent
    let pad: PadContent
    let mac: MacContent
    let tv: TVContent

    public func body(content: Content) -> some View {
        #if os(macOS)
        content.overlay(mac)
        #elseif os(tvOS)
        content.overlay(tv)
        #elseif os(visionOS)
        content.overlay(pad) // visionOS 用 iPad 布局
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.overlay(pad)
        } else {
            content.overlay(phone)
        }
        #endif
    }
}

// MARK: - Platform Constants

public enum PlatformConstants {
    /// 导航栏高度
    public static var navigationBarHeight: CGFloat {
        #if os(macOS)
        return 32
        #elseif os(tvOS)
        return 0
        #elseif os(visionOS)
        return 44
        #else
        return 44
        #endif
    }

    /// 最小触控目标尺寸
    public static var minimumTapTarget: CGFloat {
        #if os(tvOS)
        return 60
        #elseif os(iOS) || os(visionOS)
        return 44
        #else
        return 32
        #endif
    }

    /// 列表行高
    public static var listRowHeight: CGFloat {
        #if os(tvOS)
        return 80
        #elseif os(macOS)
        return 32
        #else
        return 44
        #endif
    }

    /// 缩略图大小
    public static var thumbnailSize: CGSize {
        #if os(tvOS)
        return CGSize(width: 160, height: 90)
        #elseif os(macOS)
        return CGSize(width: 120, height: 68)
        #else
        return CGSize(width: 80, height: 45)
        #endif
    }

    /// 间距
    public static var spacing: CGFloat {
        #if os(tvOS)
        return 40
        #elseif os(macOS)
        return 16
        #else
        return 12
        #endif
    }

    /// 圆角
    public static var cornerRadius: CGFloat {
        #if os(tvOS)
        return 12
        #elseif os(macOS)
        return 6
        #else
        return 8
        #endif
    }
}

// MARK: - View Extension

public extension View {
    /// 平台自适应：根据当前平台应用不同修饰符
    @ViewBuilder
    func platformGroup<Content: View>(@ViewBuilder content: @escaping (Self) -> Content) -> some View {
        content(self)
    }

    /// 条件编译修饰符
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    #if os(tvOS)
    /// tvOS 焦点样式
    func tvOSCardStyle() -> some View {
        self
            .focusable()
            .buttonStyle(.card)
    }
    #endif
}

// MARK: - Device Type Detection

#if os(iOS)
public extension UIDevice {
    static var isIPad: Bool {
        current.userInterfaceIdiom == .pad
    }

    static var isIPhone: Bool {
        current.userInterfaceIdiom == .phone
    }

    static var isVision: Bool {
        current.userInterfaceIdiom == .vision
    }
}
#endif

// MARK: - Color Extensions

public extension Color {
    static let platformBackground: Color = {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #elseif os(tvOS)
        return Color.black
        #else
        return Color(.systemBackground)
        #endif
    }()

    static let platformSecondaryBackground: Color = {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #elseif os(tvOS)
        return Color(white: 0.15)
        #else
        return Color(.secondarySystemBackground)
        #endif
    }()

    static let platformGroupedBackground: Color = {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #elseif os(tvOS)
        return Color(white: 0.1)
        #else
        return Color(.systemGroupedBackground)
        #endif
    }()

    static let platformSeparator: Color = {
        #if os(macOS)
        return Color(NSColor.separatorColor)
        #elseif os(tvOS)
        return Color(white: 0.3)
        #else
        return Color(.separator)
        #endif
    }()
}

// MARK: - Image Extensions

public extension Image {
    static func platformSymbol(_ name: String) -> Image {
        Image(systemName: name)
    }
}