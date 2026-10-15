//
//  ToolsView.swift
//  TalaMixer
//
//  Routing, monitor bus, USB recorder and the OSC inspector, in one tab.
//

import SwiftUI

struct ToolsView: View {
    enum Tool: String, CaseIterable, Identifiable {
        case meters = "Meters"
        case routing = "Routing"
        case monitor = "Monitor"
        case recorder = "Recorder"
        case inspector = "OSC"
        var id: String { rawValue }
    }

    @State private var tool: Tool = .meters

    var body: some View {
        PageScaffold("Tools", subtitle: "meters · routing · monitor · recorder · osc") {
            VStack(spacing: 16) {
                SegmentedControl(
                    options: Tool.allCases.map { .init(value: $0, label: $0.rawValue) },
                    selection: tool
                ) { tool = $0 }

                switch tool {
                case .meters: MetersContent()
                case .routing: RoutingContent()
                case .monitor: MonitorContent()
                case .recorder: RecorderContent()
                case .inspector: OSCInspectorContent()
                }
            }
        }
    }
}
