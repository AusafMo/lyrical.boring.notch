//
//  NotchHomeView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct LyricsView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let width: CGFloat
    
    @State private var opacity: Double = 1.0
    @State private var currentLyricLine: String = ""
    @State private var nextLyricLine: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let lyrics = musicManager.lyricsService.currentLyrics {
                lyricsDisplay(lyrics: lyrics)
            } else if musicManager.lyricsService.isLoading {
                loadingView
            } else if musicManager.lyricsService.error != nil {
                errorView
            } else {
                noLyricsView
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateCurrentLine()
        }
        .onAppear {
            updateCurrentLine()
        }
    }
    
    private func lyricsDisplay(lyrics: LyricsResponse) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            // Current line (highlighted)
            if !currentLyricLine.isEmpty {
                Text(currentLyricLine)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .opacity(opacity)
                    .animation(.easeInOut(duration: 0.3), value: currentLyricLine)
            } else if !nextLyricLine.isEmpty {
                // Show next upcoming line if no current line
                Text(nextLyricLine)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .opacity(0.7)
            } else {
                Text("♪ ♫ ♪")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .opacity(0.5)
            }
            
            // Song name and artist name with sync status (smaller, below lyrics)
            HStack {
                Text("\(musicManager.songTitle) - \(musicManager.artistName)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .opacity(0.8)
                    .lineLimit(1)

                if lyrics.isTimedLyrics {
                    Text("SYNCED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(2)
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list")
                    .font(.headline)
                    .foregroundColor(.white)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Loading lyrics...")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Trying LRCLIB → Lyrics.ovh")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .opacity(0.7)
                }
            }
            Text(musicManager.artistName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
    }
    
    private var errorView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "text.slash")
                    .font(.headline)
                    .foregroundColor(.gray)

                Text("No lyrics found")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
            Text(musicManager.artistName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
    }
    
    private var noLyricsView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "music.quarternote.3")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Lyrics mode")
                    .font(.headline)
                    .foregroundColor(.white)

                if let lyrics = musicManager.lyricsService.currentLyrics, lyrics.isTimedLyrics {
                    Text("SYNCED")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            Text(musicManager.artistName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.gray)
        }
    }
    
    private func updateCurrentLine() {
        guard let lyrics = musicManager.lyricsService.currentLyrics else {
            currentLyricLine = ""
            nextLyricLine = ""
            return
        }
        
        // Calculate real current time like the progress bar does
        let timeDifference = musicManager.isPlaying ? Date().timeIntervalSince(musicManager.timestampDate) : 0
        let currentTime = musicManager.elapsedTime + (timeDifference * musicManager.playbackRate)
        
        // Get current line
        if let currentLine = musicManager.lyricsService.getCurrentLine(at: currentTime) {
            if currentLyricLine != currentLine.text {
                currentLyricLine = currentLine.text
                print("🎵 [LyricsView] Current line: \(currentLine.text) at \(String(format: "%.1f", currentTime))s (raw: \(String(format: "%.1f", musicManager.elapsedTime))s)")
            }
        } else {
            currentLyricLine = ""
        }
        
        // Get next line for preview
        if let nextLine = lyrics.lines.first(where: { $0.startTime > currentTime }) {
            if nextLyricLine != nextLine.text {
                nextLyricLine = nextLine.text
            }
        } else {
            nextLyricLine = ""
        }
        
        // Add subtle animation to current lyrics line
        withAnimation(.easeInOut(duration: 0.2)) {
            opacity = opacity == 1.0 ? 0.9 : 1.0
        }
    }
}

struct MusicPlayerView: View {
    @EnvironmentObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView().drawingGroup().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: BoringViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: BoringViewModel
        @ObservedObject var webcamManager = WebcamManager.shared
    @State private var sliderValue: Double = 0
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        Group {
            if musicManager.isLyricsMode {
                // Fork: dedicated full lyrics view
                LyricsView(width: width)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    MarqueeText(
                        $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                        frameWidth: width)
                    MarqueeText(
                        $musicManager.artistName,
                        font: .headline,
                        nsFont: .headline,
                        textColor: Defaults[.playerColorTinting]
                            ? Color(nsColor: musicManager.avgColor)
                                .ensureMinimumBrightness(factor: 0.6) : .gray,
                        frameWidth: width
                    )
                    .fontWeight(.medium)
                    // Upstream: inline single-line lyrics under the artist name
                    if Defaults[.enableLyrics] {
                        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                            let currentElapsed: Double = {
                                guard musicManager.isPlaying else { return musicManager.elapsedTime }
                                let delta = timeline.date.timeIntervalSince(musicManager.timestampDate)
                                let progressed = musicManager.elapsedTime + (delta * musicManager.playbackRate)
                                return min(max(progressed, 0), musicManager.songDuration)
                            }()
                            let line: String = {
                                if musicManager.isFetchingLyrics { return "Loading lyrics…" }
                                if !musicManager.syncedLyrics.isEmpty {
                                    return musicManager.lyricLine(at: currentElapsed)
                                }
                                let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                                return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
                            }()
                            let isPersian = line.unicodeScalars.contains { scalar in
                                let v = scalar.value
                                return v >= 0x0600 && v <= 0x06FF
                            }
                            MarqueeText(
                                .constant(line),
                                font: .subheadline,
                                nsFont: .subheadline,
                                textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
                                frameWidth: width
                            )
                            .font(isPersian ? .custom("Vazirmatn-Regular", size: NSFont.preferredFont(forTextStyle: .subheadline).pointSize) : .subheadline)
                            .lineLimit(1)
                            .opacity(musicManager.isPlaying ? 1 : 0)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
            }
        }
    }

    private var musicSlider: some View {
        TimelineView(.animation(minimumInterval: musicManager.playbackRate > 0 ? 0.1 : nil)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying
            ) { newValue in
                MusicManager.shared.seek(to: newValue)
            }
            .padding(.top, 5)
            .frame(height: 36)
        }
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        // If calendar and camera are both visible alongside music, hide the edge slots
        let shouldHideEdges = Defaults[.showCalendar] && Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
        if shouldHideEdges && result.count >= 5 {
            return Array(result.dropFirst().dropLast())
        }

        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return Defaults[.playerColorTinting]
                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8)
                : .accentColor
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
    }

    private var shouldShowCamera: Bool {
        Defaults[.showMirror] && webcamManager.cameraAvailable && vm.isCameraExpanded
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: (shouldShowCamera && Defaults[.showCalendar]) ? 10 : 15) {
            MusicPlayerView(albumArtNamespace: albumArtNamespace)

            if Defaults[.showCalendar] {
                CalendarView()
                    .frame(width: shouldShowCamera ? 170 : 215)
                    .onHover { isHovering in
                        vm.isHoveringCalendar = isHovering
                    }
                    .environmentObject(vm)
                    .transition(.opacity)
            }

            if shouldShowCamera {
                CameraPreviewView(webcamManager: webcamManager)
                    .scaledToFit()
                    .opacity(vm.notchState == .closed ? 0 : 1)
                    .blur(radius: vm.notchState == .closed ? 20 : 0)
                    .animation(.interactiveSpring(response: 0.32, dampingFraction: 0.76, blendDuration: 0), value: shouldShowCamera)
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    var onValueChange: (Double) -> Void


    var body: some View {
        VStack {
            CustomSlider(
                value: $sliderValue,
                range: 0...duration,
                color: Defaults[.sliderColor] == SliderColorEnum.albumArt
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.8)
                    : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white,
                dragging: $dragging,
                lastDragged: $lastDragged,
                onValueChange: onValueChange
            )
            .frame(height: 10, alignment: .center)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(timeString(from: duration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onChange(of: currentDate) {
           guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            sliderValue = MusicManager.shared.estimatedPlaybackPosition(at: currentDate)
        }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
