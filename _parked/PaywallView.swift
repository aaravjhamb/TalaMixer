//
//  PaywallView.swift
//  TalaMixer
//
//  The full-mode subscription sheet. Simplified mode stays free; this unlocks
//  the complete surface.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(LicenseStore.self) private var license
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    featurePanel
                    productsPanel

                    Button {
                        Task { await license.restore() }
                    } label: {
                        Text("Restore purchase")
                            .themeBody(12, weight: .semibold)
                            .foregroundStyle(Theme.textSecondary)
                            .minimumHitTarget()
                    }
                    .buttonStyle(.plain)
                    .disabled(license.isWorking)

                    if let error = license.lastError {
                        Text(error)
                            .themeBody(11)
                            .foregroundStyle(Theme.mute)
                            .multilineTextAlignment(.center)
                    }

                    Text("Subscriptions renew automatically until cancelled in Settings. Payment is charged to your Apple Account.")
                        .themeBody(10)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .presentationSizing(.form)
        .presentationBackground(Theme.background)
        .onChange(of: license.isFull) { _, isFull in
            if isFull { dismiss() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Full mode")
                    .themeTitle(21)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("the complete surface")
                    .themeSectionLabel(12)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    // MARK: Features

    private var featurePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("What unlocks")

            feature("slider.vertical.3", "Every strip",
                    "Buses, FX sends and DCAs alongside the channels")
            feature("waveform.path.ecg", "Full processing",
                    "Parametric EQ with response curve, gate and compressor with sidechain")
            feature("wand.and.sparkles", "Effects rack",
                    "Four stereo engines with named parameters")
            feature("camera.aperture", "Snapshots",
                    "All 64 desk scenes with recall safes")
            feature("wrench.and.screwdriver", "Tools",
                    "Meters with RTA, routing, USB recorder, OSC inspector")

            Text("Simplified mode — faders, mutes, monitor mixes and basic channel controls — is free, always.")
                .themeBody(11)
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)
        }
        .panel()
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.goldSoft)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .themeBody(13, weight: .bold)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .themeBody(11)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: Products

    private var productsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Plans")

            if license.products.isEmpty {
                Text("No plans loaded yet.")
                    .themeBody(11)
                    .foregroundStyle(Theme.textTertiary)

                ToggleChip(title: "Try again", isOn: false) {
                    Task { await license.loadProducts() }
                }
            } else {
                ForEach(license.products, id: \.id) { product in
                    productButton(product)
                }
            }
        }
        .panel()
    }

    private func productButton(_ product: Product) -> some View {
        Button {
            Haptics.tap()
            Task { await license.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(product.displayName)
                        .themeBody(13, weight: .bold)
                        .foregroundStyle(Color.black.opacity(0.85))
                    if let period = periodText(product) {
                        Text(period)
                            .themeBody(10, weight: .medium)
                            .foregroundStyle(Color.black.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
                Text(product.displayPrice)
                    .font(Theme.value(16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metric.cornerMedium, style: .continuous)
                    .fill(Theme.gold)
            )
        }
        .buttonStyle(Pressable())
        .disabled(license.isWorking)
        .opacity(license.isWorking ? 0.6 : 1)
    }

    private func periodText(_ product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .month: return "per month"
        case .year: return "per year"
        case .week: return "per week"
        case .day: return "per day"
        @unknown default: return nil
        }
    }
}
