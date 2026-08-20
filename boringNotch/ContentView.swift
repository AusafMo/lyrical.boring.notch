//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.lyricsGradient) var lyricsGradient

    @Default(.showNotHumanFace) var showNotHumanFace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    // Lyrics state for active updates (fork)
    @State private var currentLyricDisplay: String = ""
    @State private var nextLyricDisplay: String = ""
    @State private var upcomingLyricDisplay: String = ""  // For stacked mode
    @State private var furtherLyricDisplay: String = ""   // For stacked mode
    @State private var currentLineIndex: Int = 0
    @State private var isLeftSideActive: Bool = true // For alternating mode

    // Helper to determine if current display has a notch (fork)
    private var hasNotch: Bool {
        let currentScreen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        return (currentScreen?.safeAreaInsets.top ?? 0) > 0
    }

    // Get lyrics display mode for current screen (per-display setting with fallback to global) (fork)
    // perDisplayLyricsMode is keyed by screen localizedName (see Settings/Appearance picker),
    // so resolve the current screen UUID back to its name.
    private var currentDisplayLyricsMode: LyricsDisplayMode {
        guard let screenName = vm.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) })?.localizedName else {
            return Defaults[.lyricsDisplayMode]
        }
        return Defaults[.perDisplayLyricsMode][screenName] ?? Defaults[.lyricsDisplayMode]
    }

    // Extended notch bar with lyrics (fork) — renders as one continuous element
    @ViewBuilder
    private var lyricsNotchBar: some View {
        if musicManager.isLyricsMode && vm.notchState == .closed && musicManager.isPlaying {
            // Single unified container with gradient background and content
            GeometryReader { geometry in
                ZStack(alignment: .center) {
                    // Single continuous background: top fill + gradient bar
                    VStack(spacing: 0) {
                        // Top extension to screen edge
                        Rectangle()
                            .fill(.black)
                            .frame(height: 20)

                        // Main gradient bar (conditional based on settings)
                        if lyricsGradient {
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color(nsColor: musicManager.avgColor).opacity(0.3), location: 0.0),
                                    .init(color: Color.black, location: 0.25),
                                    .init(color: Color.black, location: 0.75),
                                    .init(color: Color(nsColor: musicManager.avgColor).opacity(0.3), location: 1.0)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(height: vm.effectiveClosedNotchHeight)
                        } else {
                            Rectangle()
                                .fill(.black)
                                .frame(height: vm.effectiveClosedNotchHeight)
                        }
                    }
                    .frame(height: vm.effectiveClosedNotchHeight + 20)

                    // Lyrics content overlaid on top
                    Group {
                        if currentDisplayLyricsMode == .stacked {
                            // Stacked mode: layout depends on whether display has notch
                            if !hasNotch {
                                // No notch: single column vertical stack (full width)
                                VStack(spacing: 4) {
                                    // Next line on top (dimmed)
                                    FloatingLyricsBubbleStackedSingle(isNext: true)
                                        .transition(.move(edge: .top).combined(with: .opacity))

                                    // Current line on bottom (highlighted)
                                    FloatingLyricsBubbleStackedSingle(isNext: false)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, 16)
                            } else {
                                // Has notch: 2x2 grid layout
                                VStack(spacing: 3) {
                                    // Top row (current + next) - highlighted
                                    HStack(spacing: 0) {
                                        FloatingLyricsBubbleStackedGrid(line: currentLyricDisplay, isHighlighted: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Spacer()
                                            .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                        FloatingLyricsBubbleStackedGrid(line: nextLyricDisplay, isHighlighted: true)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }

                                    // Bottom row (upcoming + further) - dimmed
                                    HStack(spacing: 0) {
                                        FloatingLyricsBubbleStackedGrid(line: upcomingLyricDisplay, isHighlighted: false)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Spacer()
                                            .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                        FloatingLyricsBubbleStackedGrid(line: furtherLyricDisplay, isHighlighted: false)
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .frame(height: vm.effectiveClosedNotchHeight)
                                .offset(y: 20 / 2)
                            }
                        } else {
                            // Flowing or Alternating mode: horizontal layout
                            HStack(spacing: 0) {
                                // Left lyrics bubble
                                FloatingLyricsBubble()
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                // Center notch spacing
                                Spacer()
                                    .frame(width: vm.closedNotchSize.width + (cornerRadiusInsets.closed.bottom * 2))

                                // Right lyrics bubble
                                FloatingLyricsBubbleRight()
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .frame(height: vm.effectiveClosedNotchHeight)
                            .offset(y: 20 / 2)  // Offset to align with gradient bar, not top fill
                        }
                    }
                }
            }
            .frame(height: vm.effectiveClosedNotchHeight + 20)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: cornerRadiusInsets.closed.bottom,
                    bottomTrailingRadius: cornerRadiusInsets.closed.bottom,
                    topTrailingRadius: 0
                )
            )
            .offset(y: -20)  // Pull up by top fill height to connect to screen edge
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
            .onHover { hovering in
                if Defaults[.openNotchOnHover] {
                    handleHover(hovering)
                } else {
                    if (vm.notchState == .closed) && Defaults[.enableHaptics] {
                        haptics.toggle()
                    }

                    withAnimation(vm.animation) {
                        isHovering = hovering
                    }

                    if !hovering && vm.notchState == .open {
                        vm.close()
                    }
                }
            }
        }
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            // Fork: extended notch bar with lyrics (renders above the main layout when in lyrics mode)
            lyricsNotchBar

            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          if !musicManager.isLyricsMode {
                              MusicLiveActivity()
                                  .frame(alignment: .center)
                          }
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    // MARK: - Lyrics Grid Components

    @ViewBuilder
    func AmbientLyricsActivity() -> some View {
        let lyricsHeight: CGFloat = 38 // Height decreased by 2px
        
        // Left-aligned dynamic island with lyrics
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                // Music icon
                Image(systemName: "music.note")
                    .font(.caption)
                    .foregroundColor(.white)
                    .opacity(0.7)
                
                // Lyrics content
                VStack(spacing: 3) {
                    // Current line
                    Text(getCurrentDisplayLine() ?? "♪ ♫ ♪")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 250, alignment: .leading)
                    
                    // Next line (smaller)
                    Text(getNextDisplayLine() ?? "♪ ♫ ♪")
                        .font(.caption2)
                        .fontWeight(.regular)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .frame(maxWidth: 250, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: lyricsHeight / 2)
                    .fill(.black)
            )
            .frame(minWidth: 300, maxWidth: 400)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 20)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            // This will trigger UI updates for real-time lyrics
        }
    }
    
    private func getCurrentLyricsTime() -> Double {
        let timeDifference = musicManager.isPlaying ? Date().timeIntervalSince(musicManager.timestampDate) : 0
        return musicManager.elapsedTime + (timeDifference * musicManager.playbackRate)
    }
    
    private func getNextLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the next line after the current one
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let nextIndex = currentIndex + 1
            if nextIndex < lyrics.lines.count {
                return lyrics.lines[nextIndex].text
            }
        }
        
        // Fallback: find any line that starts after current time
        if let nextLine = lyrics.lines.first(where: { $0.startTime > currentTime }) {
            return nextLine.text
        }
        
        return "♪ ♫ ♪"
    }
    
    private func getUpcomingLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the line after next
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let upcomingIndex = currentIndex + 2
            if upcomingIndex < lyrics.lines.count {
                return lyrics.lines[upcomingIndex].text
            }
        }
        
        return "♪ ♫ ♪"
    }
    
    private func getFurtherLyricLine() -> String {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return "♪ ♫ ♪" }
        let currentTime = getCurrentLyricsTime()
        
        // Get current line first
        let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime)
        
        // Find the line after upcoming
        if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine?.text && $0.startTime == currentLine?.startTime }) {
            let furtherIndex = currentIndex + 3
            if furtherIndex < lyrics.lines.count {
                return lyrics.lines[furtherIndex].text
            }
        }
        
        return "♪ ♫ ♪"
    }
    
    // New display functions that handle early playback times better
    private func getCurrentDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line at this time, use it
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            return currentLine.text
        }
        
        // If no current line and we're early in the song, show the first line
        if currentTime < 10.0 && !lyrics.lines.isEmpty {
            return lyrics.lines[0].text
        }
        
        return nil
    }
    
    private func getNextDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line, find the next one
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let nextIndex = currentIndex + 1
                if nextIndex < lyrics.lines.count {
                    return lyrics.lines[nextIndex].text
                }
            }
        }
        
        // If no current line and we're early in the song, show the second line
        if currentTime < 10.0 && lyrics.lines.count > 1 {
            return lyrics.lines[1].text
        }
        
        return nil
    }
    
    private func getUpcomingDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()
        
        // If we have a current line, find the line after next
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let upcomingIndex = currentIndex + 2
                if upcomingIndex < lyrics.lines.count {
                    return lyrics.lines[upcomingIndex].text
                }
            }
        }
        
        // If no current line and we're early in the song, show the third line
        if currentTime < 10.0 && lyrics.lines.count > 2 {
            return lyrics.lines[2].text
        }
        
        return nil
    }
    
    private func getFurtherDisplayLine() -> String? {
        guard let lyrics = musicManager.lyricsService.currentLyrics else { return nil }
        let currentTime = getCurrentLyricsTime()

        // If we have a current line, find the line after upcoming
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if let currentIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {
                let furtherIndex = currentIndex + 3
                if furtherIndex < lyrics.lines.count {
                    return lyrics.lines[furtherIndex].text
                }
            }
        }

        // If no current line and we're early in the song, show the fourth line
        if currentTime < 10.0 && lyrics.lines.count > 3 {
            return lyrics.lines[3].text
        }

        return nil
    }

    // Update lyrics display for real-time updates
    private func updateLyricsDisplay() {
        guard let lyrics = musicManager.lyricsService.currentLyrics else {
            currentLyricDisplay = ""
            nextLyricDisplay = ""
            upcomingLyricDisplay = ""
            furtherLyricDisplay = ""
            currentLineIndex = 0
            return
        }

        let currentTime = getCurrentLyricsTime()

        // Find current line and its index
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime),
           let foundIndex = lyrics.lines.firstIndex(where: { $0.text == currentLine.text && $0.startTime == currentLine.startTime }) {

            // Check if we've moved to a new line
            let lineChanged = foundIndex != currentLineIndex

            if lineChanged {
                currentLineIndex = foundIndex

                // Toggle active side for alternating mode
                if currentDisplayLyricsMode == .alternating {
                    isLeftSideActive.toggle()
                }
            }

            // Update display text
            if currentLyricDisplay != currentLine.text {
                currentLyricDisplay = currentLine.text
            }

            // Update next line
            let nextIndex = foundIndex + 1
            if nextIndex < lyrics.lines.count {
                if nextLyricDisplay != lyrics.lines[nextIndex].text {
                    nextLyricDisplay = lyrics.lines[nextIndex].text
                }
            } else {
                nextLyricDisplay = ""
            }

            // Update upcoming line (for stacked mode)
            let upcomingIndex = foundIndex + 2
            if upcomingIndex < lyrics.lines.count {
                if upcomingLyricDisplay != lyrics.lines[upcomingIndex].text {
                    upcomingLyricDisplay = lyrics.lines[upcomingIndex].text
                }
            } else {
                upcomingLyricDisplay = ""
            }

            // Update further line (for stacked mode)
            let furtherIndex = foundIndex + 3
            if furtherIndex < lyrics.lines.count {
                if furtherLyricDisplay != lyrics.lines[furtherIndex].text {
                    furtherLyricDisplay = lyrics.lines[furtherIndex].text
                }
            } else {
                furtherLyricDisplay = ""
            }
        } else {
            currentLyricDisplay = ""
            nextLyricDisplay = ""
            upcomingLyricDisplay = ""
            furtherLyricDisplay = ""
        }
    }

    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    // MARK: - Floating Lyrics Bubble

    @ViewBuilder
    func FloatingLyricsBubble() -> some View {
        let displayMode = currentDisplayLyricsMode
        let isFlowing = displayMode == .flowing
        let isAlternating = displayMode == .alternating

        HStack(alignment: .center, spacing: 8) {
            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)

            if isHovering {
                // Show song name when hovering
                Text(musicManager.songTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(0.9)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Show lyrics based on mode
                if isFlowing {
                    // Flowing mode: always show current line on left
                    Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(0.9)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isAlternating {
                    // Alternating mode: show current if left is active, next if not
                    if isLeftSideActive {
                        Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .opacity(0.95)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .opacity(0.5)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleRight() -> some View {
        let displayMode = currentDisplayLyricsMode
        let isFlowing = displayMode == .flowing
        let isAlternating = displayMode == .alternating

        HStack(alignment: .center, spacing: 8) {
            // Show lyrics based on mode
            if isFlowing {
                // Flowing mode: always show next line on right (dimmed)
                Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isAlternating {
                // Alternating mode: show current if right is active, next if not
                if !isLeftSideActive {
                    Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(0.95)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .opacity(0.5)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleStackedSingle(isNext: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Music icon on left
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)

            // Lyrics text (centered)
            if isNext {
                // Next line (dimmed, on top)
                Text(nextLyricDisplay.isEmpty ? "♪ ♫ ♪" : nextLyricDisplay)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .opacity(0.6)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // Current line (highlighted, on bottom)
                Text(currentLyricDisplay.isEmpty ? "♪ ♫ ♪" : currentLyricDisplay)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(0.95)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Music icon on right
            Image(systemName: "music.note")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }

    @ViewBuilder
    func FloatingLyricsBubbleStackedGrid(line: String, isHighlighted: Bool) -> some View {
        HStack(alignment: .center, spacing: 6) {
            // Music icon
            Image(systemName: "music.note")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .opacity(isHighlighted ? 0.7 : 0.5)

            // Lyrics text
            Text(line.isEmpty ? "♪ ♫ ♪" : line)
                .font(.system(size: 11, weight: isHighlighted ? .semibold : .regular))
                .foregroundColor(.white)
                .opacity(isHighlighted ? 0.9 : 0.5)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateLyricsDisplay()
        }
        .onAppear {
            updateLyricsDisplay()
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
