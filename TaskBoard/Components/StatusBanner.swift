//
//  StatusBanner.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct BannerMessage: Equatable {
    let text: String
    let systemImage: String
    let tint: Color
    let autoDismissAfter: TimeInterval?   // nil = stays until explicitly cleared

    static let offline = BannerMessage(
        text: "You're offline — changes will sync when you reconnect",
        systemImage: "wifi.slash", tint: .orange, autoDismissAfter: 3)

    static let backOnline = BannerMessage(
        text: "Back online — syncing",
        systemImage: "wifi", tint: .green, autoDismissAfter: 2)

    static let syncSuccess = BannerMessage(
        text: "All changes synced",
        systemImage: "checkmark.circle", tint: .green, autoDismissAfter: 2)
}

/// Pure presentation: whoever owns the root view decides which message applies.
struct StatusBanner: View {
    let message: BannerMessage?

    var body: some View {
        Group {
            if let message {
                HStack(spacing: 10) {
                    Image(systemName: message.systemImage)
                        .font(.footnote.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))

                    Text(message.text)
                        .font(.footnote.weight(.medium))
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(message.tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Opaque backing: this floats over the board rather than sitting
                // in its own strip.
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.regularMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(message.tint.opacity(0.18))
                        }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(message.tint.opacity(0.35), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                // Must stay inset. A background touching the top edge gets sampled
                // by the navigation bar, tinting the whole status bar.
                .padding(.horizontal, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.45), value: message)
    }
}
