//
//  HomeWidgetBundle.swift
//  HomeWidgetExtension
//
//  Spec 030 — TimerWidget: Home Screen + Lock Screen + StandBy widget bundle.
//

import SwiftUI
import WidgetKit

@main
struct HomeWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimerWidget()
    }
}
