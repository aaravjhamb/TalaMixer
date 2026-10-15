//
//  PanelScaffold.swift
//  TalaMixer
//
//  Shared chrome: `PageScaffold` for the main tab pages (serif title, no
//  dismiss), and `PanelScaffold` for presented sheets.
//

import SwiftUI

// MARK: - Tab page

struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var toolbar: AnyView?
    var content: Content

    init(_ title: String,
         subtitle: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.toolbar = nil
        self.content = content()
    }

    init<T: View>(_ title: String,
                  subtitle: String? = nil,
                  @ViewBuilder toolbar: () -> T,
                  @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.toolbar = AnyView(toolbar())
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .themeTitle(30)
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitle {
                            Text(subtitle.lowercased())
                                .themeSectionLabel(13)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let toolbar { toolbar }
                }

                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, Theme.Metric.tabBarClearance)
        }
        .background(Theme.background)
    }
}

// MARK: - Sheet

/// Which sheet size a panel wants.
///
/// `PresentationSizing` is a protocol, so it can't be stored as a property and
/// then handed back to `presentationSizing(_:)` — that call needs a concrete
/// type. This enum carries the choice and resolves it at the call site.
enum PanelSizing {
    /// Large — for anything with a graph or a wide grid.
    case page
    /// Narrower, form-like — for lists of settings.
    case form
}

struct PanelScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    var subtitle: String?
    var sizing: PanelSizing = .page
    var toolbar: AnyView?
    var content: Content

    init(_ title: String,
         subtitle: String? = nil,
         sizing: PanelSizing = .page,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.sizing = sizing
        self.toolbar = nil
        self.content = content()
    }

    init<T: View>(_ title: String,
                  subtitle: String? = nil,
                  sizing: PanelSizing = .page,
                  @ViewBuilder toolbar: () -> T,
                  @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.sizing = sizing
        self.toolbar = AnyView(toolbar())
        self.content = content()
    }

    var body: some View {
        switch sizing {
        case .page: base.presentationSizing(.page)
        case .form: base.presentationSizing(.form)
        }
    }

    private var base: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(18)
            }
        }
        .background(Theme.background)
        .presentationBackground(Theme.background)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .themeTitle(21)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle.lowercased())
                        .themeSectionLabel(12)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if let toolbar { toolbar }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.surfaceRaised))
                    .minimumHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(16)
        .background(Theme.surface)
    }
}
