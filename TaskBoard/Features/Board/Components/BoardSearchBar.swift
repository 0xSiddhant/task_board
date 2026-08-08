//
//  BoardSearchBar.swift
//  TaskBoard
//
//  Created by Siddhant Kumar on 08/08/26.
//

import SwiftUI

struct BoardSearchBar: View {
    @Binding var text: String
    let matchCount: Int
    let showsResultCount: Bool
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                field
                Button("Cancel", action: onDismiss)
                    .font(.subheadline)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if showsResultCount {
                Text(resultSummary)
                    .font(.caption)
                    .foregroundStyle(matchCount == 0 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                    .padding(.leading, 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: showsResultCount)
        .animation(.smooth(duration: 0.25), value: matchCount)
        // Focus on appear, so the keyboard comes up without a second tap.
        .onAppear { isFocused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Search tasks", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                isFocused ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(.quaternary),
                lineWidth: 1
            )
        }
        .animation(.smooth(duration: 0.2), value: text.isEmpty)
        .animation(.smooth(duration: 0.2), value: isFocused)
    }

    private var resultSummary: String {
        switch matchCount {
        case 0: return "No matching tasks"
        case 1: return "1 match"
        default: return "\(matchCount) matches"
        }
    }
}
