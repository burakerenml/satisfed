//
//  LogFlowView.swift
//  Shiphaton App
//
//  The core flow, camera-first: snap what you're eating (or type it) →
//  see what it already brings and add boosts → save. Add, never subtract.
//

import SwiftUI
import SwiftData
import PhotosUI

struct LogFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = SnapCamera()

    @State private var step: Step = .snap
    @State private var snappedImage: UIImage?
    @State private var libraryItem: PhotosPickerItem?
    @State private var flash = false
    @State private var selectedFood: Food?
    @State private var typedName = ""
    /// Meals added on this device, merged into the grid ahead of the
    /// built-in library. Reloaded whenever one is added.
    @State private var customFoods: [Food] = CustomFoodStore.all()
    /// The emoji riding along with a meal that's about to be added. Empty
    /// until the person picks one; the plate stands in at save time.
    @State private var newFoodEmoji = ""
    @State private var deck = SuggestionDeckModel()
    /// Bumped by the "type it instead" tap, so the button answers with a
    /// ring rather than a highlight it would carry off the screen.
    @State private var typePulses = 0
    @State private var saved = false

    // MARK: - Snap analysis (vision)

    @State private var isAnalyzingPhoto = false
    /// Warm retry copy when the photo wasn't food at all.
    @State private var photoNotice: String?
    /// Why the photo couldn't be read at all (offline, the AI down), in
    /// plain words. The read step shows it with a retry.
    @State private var analysisError: String?
    @State private var analysisOffline = false
    /// The gate refused the read: the free round is spent.
    @State private var analysisLocked = false
    /// Something went wrong before a photo even landed: the shutter
    /// failed, or a library pick couldn't be opened. Shown on the snap step.
    @State private var snapNotice: String?
    /// Menu wing-person picks, shown instead of the food grid.
    @State private var menuAnalysis: SnackAnalysis?
    /// True while the build step is running on an AI-identified plate
    /// rather than a picked/typed food. Cleared the moment the person
    /// edits away from what was pre-filled.
    @State private var usingAIPlate = false
    @State private var aiCraving: String?
    @State private var aiBaseCompounds: Set<Compound> = []
    @State private var aiPrefillText = ""

    /// Extra hook for flows that hand off here (e.g. the craving
    /// translator) and want to close themselves once the meal is saved.
    var onSaved: (() -> Void)?

    /// `read` is the photo's own step: the plate gets named there, and the
    /// person can correct the name before building on it. `pick` is the
    /// typed path's grid.
    enum Step { case snap, read, pick, build }

    /// Where the build step was entered from, so back lands on the same
    /// step the person came through.
    @State private var buildCameFrom: Step = .pick

    /// Default flow starts at the camera; a prefilled food (from the
    /// craving translator or an idea card) jumps straight to the build step.
    init(prefill: Food? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        _selectedFood = State(initialValue: prefill)
        _step = State(initialValue: prefill == nil ? .snap : .build)
    }

    /// Direction-agnostic soft push between steps.
    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 14)),
            removal: .opacity
        )
    }

    #if DEBUG
    /// Screenshot hook: launch with "-uifood chocolate" to open the build step.
    private func applyDebugLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uifood"), index + 1 < arguments.count,
           let food = FoodLibrary.foods.first(where: { $0.id == arguments[index + 1] }) {
            selectedFood = food
            step = .build
        }
    }
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.canvas.ignoresSafeArea()
                switch step {
                case .snap: snapStep.transition(stepTransition)
                case .read: readStep.transition(stepTransition)
                case .pick: pickStep.transition(stepTransition)
                case .build: buildStep.transition(stepTransition)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            #if DEBUG
            .onAppear(perform: applyDebugLaunchArguments)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(stepTitle)
                        .font(.display(17))
                        .foregroundStyle(Palette.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                if step != .snap {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                }
            }
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)?.scaledDown(to: 1200) {
                    acceptPhoto(image)
                } else {
                    snapNotice = "Couldn't open that photo. Try another one, or snap it fresh."
                }
                libraryItem = nil
            }
        }
        .onChange(of: typedName) { _, newValue in
            if usingAIPlate, newValue != aiPrefillText { usingAIPlate = false }
        }
        .paywallHost(onUnlocked: resumeAfterUnlock)
    }

    /// Picks the flow back up at whatever the paywall interrupted, so
    /// subscribing continues the snack they were in the middle of instead
    /// of dropping them on a dead screen.
    private func resumeAfterUnlock() {
        switch step {
        case .snap, .pick:
            break
        case .read:
            // The photo landed but its read never did.
            if let image = snappedImage, analysisLocked || analysisError != nil {
                Task { await runSnapAnalysis(image) }
            }
        case .build:
            if deck.blocker != nil || deck.decisions.isEmpty {
                // Nothing swiped yet, or the deck was locked. Deal the
                // real one now that it's allowed.
                deck.reset()
                Task { await dealSuggestions() }
            } else {
                // Mid-deck: keep their swipes and carry on, which fetches
                // the summary now that it's allowed.
                Task { await followUpIfNeeded() }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .snap: "Snap your food"
        case .read: "Your plate"
        case .pick: "What are you eating?"
        case .build: "Let's round it out"
        }
    }

    private func goBack() {
        Haptics.soft()
        withAnimation(.spring(duration: 0.4)) {
            switch step {
            case .build:
                step = buildCameFrom
                deck.reset()
            case .pick:
                if snappedImage != nil, hasPhotoRead {
                    step = .read
                } else {
                    step = .snap
                    snappedImage = nil
                    resetPhotoAnalysis()
                }
            case .read:
                step = .snap
                snappedImage = nil
                resetPhotoAnalysis()
            case .snap:
                break
            }
        }
    }

    /// Whether the read step has anything to go back to: a result, a
    /// notice, or a read still in flight.
    private var hasPhotoRead: Bool {
        isAnalyzingPhoto || analysisLocked || analysisError != nil || photoNotice != nil
            || menuAnalysis != nil || aiCraving != nil
    }

    private func resetPhotoAnalysis() {
        photoNotice = nil
        analysisError = nil
        analysisOffline = false
        analysisLocked = false
        menuAnalysis = nil
        usingAIPlate = false
        aiCraving = nil
        aiBaseCompounds = []
        aiPrefillText = ""
    }

    /// The photo path is an AI read, so a spent free round stops here,
    /// on the paywall, rather than after a photo that can't be read.
    private var photoNeedsSubscription: Bool {
        guard SubscriptionStore.shared.needsSubscription else { return false }
        PaywallCenter.shared.request(.blocked)
        return true
    }

    private func acceptPhoto(_ image: UIImage) {
        snappedImage = image
        snapNotice = nil
        camera.stop()
        Haptics.success()
        resetPhotoAnalysis()
        typedName = ""
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            step = .read
        }
        Task { await runSnapAnalysis(image) }
    }

    /// Fires the vision bot the moment a photo lands, in parallel with the
    /// pick step already showing. Routes by `photo_type`: a plate pre-fills
    /// the name field and primes the build step's swipe deck with what was
    /// identified; a menu surfaces its picks instead of the food grid; a
    /// non-food photo gets a warm, dismissible retry nudge. Typing instead
    /// always still works no matter what comes back.
    private func runSnapAnalysis(_ image: UIImage) async {
        analysisError = nil
        analysisLocked = false
        if SubscriptionStore.shared.needsSubscription {
            analysisLocked = true
            PaywallCenter.shared.request(.blocked)
            return
        }
        if !NetworkMonitor.shared.isOnline {
            analysisOffline = true
            analysisError = AIError.offlineMessage
            return
        }
        isAnalyzingPhoto = true
        var result: SnackAnalysis?
        var failure: Error?
        do {
            result = try await ComboAIClient.analyzeSnack(
                image: image, note: "", profile: ProfileContext.aiProfile()
            )
        } catch {
            failure = error
        }
        isAnalyzingPhoto = false
        // A retake in the meantime should win over a now-stale result.
        guard snappedImage === image else { return }
        if let failure {
            if case AIError.paywallRequired = failure {
                analysisLocked = true
            } else {
                analysisOffline = AIError.isOffline(failure) || !NetworkMonitor.shared.isOnline
                analysisError = AIError.friendlyMessage(for: failure, what: "read the photo")
            }
            return
        }
        guard let result else { return }
        switch result.photoType {
        case "no_food":
            photoNotice = result.headline.isEmpty
                ? "Didn't quite catch food in that one. Another snap works, or just type it."
                : result.headline
        case "menu":
            if menuAnalysisHasPicks(result) {
                menuAnalysis = result
            } else {
                photoNotice = "Looks like a menu, but we couldn't pick anything out. Type what you're having."
            }
        case "plate":
            let items = result.identifiedItems.map(\.name)
            guard !items.isEmpty else {
                photoNotice = "We couldn't quite name that. Another snap works, or just type it."
                return
            }
            aiCraving = "my plate: " + items.joined(separator: ", ")
            aiBaseCompounds = Set(result.compoundsPresent.compactMap { Compound(aiValue: $0) })
            aiPrefillText = items.joined(separator: ", ").capitalizedFirst
            typedName = aiPrefillText
            usingAIPlate = true
        default:
            photoNotice = "We couldn't quite name that. Another snap works, or just type it."
        }
    }

    private func menuAnalysisHasPicks(_ analysis: SnackAnalysis) -> Bool {
        !allowedMenuPicks(analysis).isEmpty
    }

    /// The picks worth showing: the wing-person is told what's off the
    /// table and reads the menu inside it, and this is the net under that.
    /// A dish that names something they don't eat never reaches the card,
    /// and if that leaves nothing, the menu read says so instead.
    private func allowedMenuPicks(_ analysis: SnackAnalysis) -> [SnackAnalysis.MenuPick] {
        DietaryFilter.keep(analysis.menuPicks, name: \.item)
    }

    // MARK: - Step 0: snap

    private var snapStep: some View {
        VStack(spacing: 14) {
            // The camera is the first thing people meet now that it's the
            // bar's own button, so one line says what happens after the
            // shutter.
            VStack(spacing: 10) {
                Text("We'll suggest easy adds that make it more satisfying.")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 8)
                // How they eat, right where the promise is made: the adds
                // will keep to it, and this says so before the shutter.
                PreferenceBadges(alignment: .center)
            }
            if let snapNotice {
                NoticeBanner(text: snapNotice, kind: .nudge)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
            viewfinderCard
            typeInsteadButton
        }
        .padding(.horizontal, Metrics.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .animation(.spring(duration: 0.35), value: snapNotice)
        .task { await camera.prepare() }
        .onDisappear { camera.stop() }
    }

    private var viewfinderCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(hex: "1C202B"))

            switch camera.phase {
            case .ready:
                CameraViewfinder(session: camera.session)
            case .loading:
                ProgressView()
                    .tint(.white.opacity(0.6))
            case .denied:
                cameraFallback(
                    icon: "camera.badge.ellipsis",
                    message: "Camera access is off for this app.\nTurn it on in Settings, pick a photo, or just type it."
                )
            }

            // Shutter flash
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white)
                .opacity(flash ? 0.7 : 0)

            captureControls
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .frame(maxHeight: .infinity)
    }

    private func cameraFallback(icon: String, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(message)
                .font(.display(14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                Haptics.soft()
                SnapCamera.openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 12, weight: .bold))
                    Text("Open Settings")
                        .font(.display(14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(.white.opacity(0.18)))
            }
            .buttonStyle(BounceStyle())
            .padding(.top, 4)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 60)
    }

    /// Library · shutter · flow hint, floating at the viewfinder's foot.
    private var captureControls: some View {
        VStack {
            Spacer()
            HStack {
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.18), in: Circle())
                }

                Spacer()

                shutterButton
                    .opacity(camera.phase == .denied ? 0.25 : 1)

                Spacer()

                // Symmetry spacer matching the library button.
                Color.clear.frame(width: 46, height: 46)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
    }

    private var shutterButton: some View {
        Button {
            guard camera.phase == .ready else { return }
            // A spent free round meets the paywall here, before a photo
            // is taken that couldn't be read anyway.
            guard !photoNeedsSubscription else { return }
            Haptics.tap()
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.09)) { flash = false }
            camera.onCapture = { acceptPhoto($0) }
            camera.onCaptureFailed = {
                snapNotice = "That shot didn't come through. Give it another try."
            }
            camera.snap()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(BounceStyle())
        .accessibilityLabel("Take photo")
    }

    private var typeInsteadButton: some View {
        Button {
            Haptics.soft()
            typePulses += 1
            camera.stop()
            // Leaving a photo's read behind for the keyboard: the photo
            // stays with the meal, the AI's name for it does not.
            if step == .read {
                typedName = ""
                usingAIPlate = false
            }
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                step = .pick
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                Text("Type it instead")
                    .font(.display(16, weight: .semibold))
            }
            .foregroundStyle(Palette.roseDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            // White on the canvas; inside the read step's white cards it
            // takes the canvas colour so it still reads as a button.
            .background(Capsule().fill(step == .read ? Palette.canvas : Palette.card))
        }
        .buttonStyle(BounceStyle())
        .pulse(Capsule(), trigger: typePulses)
    }

    // MARK: - Step 1: pick

    private var pickStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let snappedImage {
                    snappedHeader(snappedImage)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.inkSoft)
                    // Results follow every keystroke, so there's no search
                    // button to press. Go just takes the closest match.
                    TextField("Search your food", text: $typedName)
                        .font(.display(16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .submitLabel(.go)
                        .autocorrectionDisabled()
                        .onSubmit(startWithTypedName)
                    if !typedName.isEmpty {
                        Button {
                            Haptics.soft()
                            typedName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Palette.inkSoft.opacity(0.5))
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Palette.card)
                )

                if searchResults.isEmpty, !searchQuery.isEmpty {
                    addMealCard(searchQuery)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(searchResults) { food in
                        Button {
                            Haptics.soft()
                            usingAIPlate = false
                            selectedFood = food
                            enterBuild(from: .pick)
                        } label: {
                            VStack(spacing: 8) {
                                Text(food.emoji)
                                    .font(.system(size: 30))
                                Text(food.name)
                                    .font(.display(13, weight: .semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Palette.card)
                            )
                        }
                        .buttonStyle(TapTileStyle())
                    }
                }
                .animation(.spring(duration: 0.35), value: searchResults)
            }
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Live search

    private var searchQuery: String {
        typedName.trimmingCharacters(in: .whitespaces)
    }

    /// What the grid shows right now: everything when nothing's typed,
    /// otherwise the matches, closest first.
    private var searchResults: [Food] {
        FoodLibrary.matches(searchQuery, in: customFoods + FoodLibrary.foods)
    }

    /// Nothing we know matched. Offer to keep it: give it an emoji of your
    /// own if you like, and it joins the grid for every log after this one.
    private func addMealCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                emojiTile
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.display(16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("New to us. Tap the tile to give it an emoji, and it's here next time.")
                        .font(.display(13, weight: .medium))
                        .foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button {
                addCustomFood(name)
            } label: {
                Text("Tap to add this meal")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .softCard(padding: 16)
    }

    /// The new meal's emoji, typed straight in: the tile is an emoji-only
    /// text box that opens the emoji keyboard, with a faded plate showing
    /// through until something's picked.
    private var emojiTile: some View {
        ZStack {
            if newFoodEmoji.isEmpty {
                Text("🍽️")
                    .font(.system(size: 30))
                    .opacity(0.35)
                    .allowsHitTesting(false)
            }
            EmojiField(emoji: $newFoodEmoji)
        }
        .frame(width: 54, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.blush.opacity(0.7))
        )
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.inkSoft)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.card))
                .offset(x: 4, y: 4)
                .allowsHitTesting(false)
        }
        .animation(.spring(duration: 0.3), value: newFoodEmoji)
        .accessibilityLabel(newFoodEmoji.isEmpty ? "Pick an emoji" : "Emoji \(newFoodEmoji), tap to change")
    }

    /// Keeps a typed meal on the device and heads straight into building
    /// on it, so adding never costs an extra tap.
    private func addCustomFood(_ name: String) {
        Haptics.success()
        let food = CustomFoodStore.add(name: name, emoji: newFoodEmoji.isEmpty ? "🍽️" : newFoodEmoji)
        customFoods = CustomFoodStore.all()
        newFoodEmoji = ""
        usingAIPlate = false
        selectedFood = food
        enterBuild(from: .pick)
    }

    /// The one way into the build step, so back always knows the way out.
    private func enterBuild(from origin: Step) {
        buildCameFrom = origin
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
            step = .build
        }
    }

    /// The menu wing-person's picks: informational, tap one to start
    /// building around it exactly like typing it would.
    private func menuPicksCard(_ analysis: SnackAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Best bets on this menu", subtitle: "Tap one to build around it")
            ForEach(Array(allowedMenuPicks(analysis).enumerated()), id: \.offset) { _, pick in
                Button {
                    Haptics.soft()
                    usingAIPlate = false
                    selectedFood = nil
                    typedName = pick.item
                    enterBuild(from: .read)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pick.item)
                                .font(.display(15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(pick.why)
                                .font(.display(12, weight: .medium))
                                .foregroundStyle(Palette.inkSoft)
                                .lineLimit(2)
                        }
                        Spacer()
                        AddsPills(adds: Set(pick.compounds.compactMap { Compound(aiValue: $0) }))
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.card))
                }
                .buttonStyle(BounceStyle())
            }
            if !analysis.orderTip.isEmpty {
                Text("💡 \(analysis.orderTip)")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.roseDeep)
                    .padding(.top, 2)
            }
        }
    }

    private func snappedHeader(_ image: UIImage) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Photo's coming along")
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("It stays with the meal once you log it.")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            Button(action: retakePhoto) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.mist))
            }
            .accessibilityLabel("Retake photo")
        }
        .softCard(padding: 12)
    }

    /// Back to the camera with nothing kept from this photo.
    private func retakePhoto() {
        Haptics.soft()
        withAnimation(.spring(duration: 0.4)) {
            step = .snap
            snappedImage = nil
            typedName = ""
            resetPhotoAnalysis()
        }
    }

    // MARK: - Step 1 (photo): read

    /// What the read step is showing right now, for animating between
    /// its cards.
    private enum ReadPhase: Equatable { case reading, locked, failed, noFood, menu, plate }

    private var readPhase: ReadPhase {
        if isAnalyzingPhoto { return .reading }
        if analysisLocked { return .locked }
        if analysisError != nil { return .failed }
        if photoNotice != nil { return .noFood }
        if menuAnalysis != nil { return .menu }
        return .plate
    }

    /// The photo, big, with what we make of it underneath. Nothing to
    /// pick from here: the plate gets named on its own, and the name is
    /// there to correct if the read is off.
    private var readStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let snappedImage {
                    photoCard(snappedImage)
                }
                Group {
                    switch readPhase {
                    case .reading: readingCard
                    case .locked: lockedReadCard
                    case .failed: failedReadCard
                    case .noFood: noFoodCard
                    case .menu: menuReadCard
                    case .plate: plateCard
                    }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .animation(.spring(duration: 0.4, bounce: 0.15), value: readPhase)
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func photoCard(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Button(action: retakePhoto) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(BounceStyle())
                .padding(10)
                .accessibilityLabel("Retake photo")
            }
            .shadow(color: Color(hex: "2E3A54").opacity(0.10), radius: 22, y: 10)
    }

    /// While the read is in flight: one line on what's happening, so a
    /// few seconds of nothing don't read as the app being stuck.
    private var readingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(Palette.rose)
                .scaleEffect(1.1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Taking a look at your plate")
                    .font(.display(15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Naming what's on it. This takes a few seconds.")
                    .font(.display(13, weight: .medium))
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .softCard(padding: 16)
    }

    /// The read landed: the name, editable in place, and one button on.
    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(usingAIPlate ? "Looks like" : "Going with")
                .font(.display(11, weight: .bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Palette.inkSoft)
                .contentTransition(.opacity)

            HStack(spacing: 10) {
                TextField("What's on the plate?", text: $typedName)
                    .font(.display(18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .onSubmit(buildOnPlate)
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Palette.canvas)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
            )

            Text(usingAIPlate
                 ? "Not quite it? Fix the name and we'll build on that instead."
                 : "Got it. We'll build on your name for it.")
                .font(.display(13, weight: .medium))
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: usingAIPlate)

            Button(action: buildOnPlate) {
                Text("Build on it")
            }
            .buttonStyle(PrimaryButtonStyle())
            .opacity(searchQuery.isEmpty ? 0.4 : 1)
            .disabled(searchQuery.isEmpty)
        }
        .softCard(padding: 16)
    }

    /// Into the build step with whatever the name field says: the AI's
    /// read as-is, or the person's correction. A correction that names a
    /// library food picks that food up, so its builders come along.
    private func buildOnPlate() {
        let name = searchQuery
        guard !name.isEmpty else { return }
        Haptics.soft()
        if usingAIPlate {
            selectedFood = nil
        } else {
            selectedFood = FoodLibrary.food(matching: name)
        }
        enterBuild(from: .read)
    }

    private var noFoodCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoticeBanner(text: photoNotice ?? "", kind: .nudge)
            Button(action: retakePhoto) {
                Text("Snap again")
            }
            .buttonStyle(PrimaryButtonStyle())
            typeInsteadButton
        }
        .softCard(padding: 16)
    }

    private var failedReadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoticeBanner(text: analysisError ?? "", kind: analysisOffline ? .offline : .trouble)
            Button {
                Haptics.soft()
                if let snappedImage {
                    Task { await runSnapAnalysis(snappedImage) }
                }
            } label: {
                Text("Try again")
            }
            .buttonStyle(PrimaryButtonStyle())
            typeInsteadButton
        }
        .softCard(padding: 16)
    }

    /// The gate said no: the free round is spent. The paywall is already
    /// up; this is what's underneath it, so closing the paywall lands on
    /// something that makes sense and still offers the typed path.
    private var lockedReadCard: some View {
        PremiumLockCard(line: "Your free round is done. Join to keep the photo reads coming, or type it in below.") {
            typeInsteadButton
        }
    }

    private var menuReadCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let menuAnalysis {
                menuPicksCard(menuAnalysis)
            }
            typeInsteadButton
        }
        .softCard(padding: 16)
    }

    private func startWithTypedName() {
        let trimmed = searchQuery
        guard !trimmed.isEmpty else { return }
        // Nothing matched, so Go means the same thing the card does: keep
        // this meal, then build on it.
        guard let match = searchResults.first ?? FoodLibrary.food(matching: trimmed) else {
            addCustomFood(trimmed)
            return
        }
        selectedFood = match
        Haptics.soft()
        enterBuild(from: .pick)
    }

    // MARK: - Step 2: build

    private var mealName: String {
        selectedFood?.name ?? typedName.trimmingCharacters(in: .whitespaces)
    }

    private var mealEmoji: String {
        selectedFood?.emoji ?? "🍽️"
    }

    /// What we know the plate brings before anyone's asked: a library
    /// food's own builders, or the vision bot's read of a snapped plate.
    /// Empty for a meal someone typed in.
    private var baseCompounds: Set<Compound> {
        if let selectedFood { return selectedFood.has }
        return usingAIPlate ? aiBaseCompounds : []
    }

    /// The base once the deck has been dealt: the swipe bot judges what
    /// the food itself brings (adana kebab → protein) and hands it back
    /// with the first deck, which is the only way a typed meal ever fills
    /// a builder on its own. Until then, and offline, it's `baseCompounds`.
    private var resolvedBase: Set<Compound> {
        baseCompounds.union(deck.base)
    }

    /// What the swipe deck builds around: the AI-identified plate when
    /// there is one and nothing's overridden it, otherwise whatever's
    /// picked or typed.
    private var cravingText: String {
        if usingAIPlate, let aiCraving { return aiCraving }
        return mealName.isEmpty ? "something to eat" : mealName
    }

    private var chosenBoosts: [Boost] {
        deck.chosen.map(\.boost)
    }

    private var currentCompounds: Set<Compound> {
        chosenBoosts.reduce(into: resolvedBase) { $0.formUnion($1.adds) }
    }

    /// The plate so far up top, the deck of easy adds below, save pinned
    /// to the foot. Right swipe adds, left swipe passes; nothing scrolls.
    private var buildStep: some View {
        VStack(spacing: 0) {
            plateHeader
                .padding(.top, 8)
                .padding(.horizontal, Metrics.screenMargin)

            SuggestionDeck(model: deck, onDecision: { _, added in
                decided(added: added)
            }, onUndo: {
                Task { await followUpIfNeeded() }
            }, onRetry: {
                deck.reset()
                Task { await dealSuggestions() }
            }, onUnlock: {
                PaywallCenter.shared.request(.blocked)
            })
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .task(id: selectedFood?.id) { await dealSuggestions() }
        .safeAreaInset(edge: .bottom) {
            // Stays put even when the deck is locked. The plate is already
            // named and already brings what it brings, and logging it as
            // is costs nothing, so the paywall is a door here and not the
            // only one.
            Button {
                save()
            } label: {
                Text(saveLabel)
                    .contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle())
            .animation(.spring(duration: 0.35), value: saveLabel)
            .padding(.horizontal, Metrics.screenMargin)
            .padding(.bottom, 8)
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: deck.blocker)
    }

    private var plateHeader: some View {
        VStack(spacing: 10) {
            ZStack {
                TrioRing(compounds: currentCompounds, size: 88, lineWidth: 8)
                // The ring speaks for what's been added; a fixed food emoji
                // dead-center stops meaning anything once a boost joins in,
                // so only a snapped photo — never the base emoji — sits here.
                if let snappedImage {
                    Image(uiImage: snappedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 66, height: 66)
                        .clipShape(Circle())
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3), value: currentCompounds)

            Text(mealDisplayName)
                .font(.display(20))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .lineSpacing(2)
                .padding(.horizontal, Metrics.spaceL)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: mealDisplayName)

            HStack(spacing: 8) {
                ForEach(Compound.allCases) { compound in
                    CompoundChip(compound: compound, filled: currentCompounds.contains(compound))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.3), value: currentCompounds)
        }
    }

    /// The plate's name grows with what's landed on it: "Cookies", then
    /// "Cookies + Cottage cheese" once the first boost is added.
    private var mealDisplayName: String {
        ([mealName] + chosenBoosts.map(\.name)).joined(separator: " + ")
    }

    private var saveLabel: String {
        chosenBoosts.isEmpty ? "Log it as is, still counts" : "All set, log it"
    }

    /// The first deck. Three things can stand in its way, and each gets
    /// its own card rather than a stand-in deck: a spent free round (the
    /// paywall comes up over it), no network, or the AI not answering.
    private func dealSuggestions() async {
        if SubscriptionStore.shared.needsSubscription {
            deck.isLoading = false
            withAnimation(.spring(duration: 0.4)) { deck.blocker = .locked }
            PaywallCenter.shared.request(.blocked)
            return
        }
        if !NetworkMonitor.shared.isOnline {
            deck.isLoading = false
            withAnimation(.spring(duration: 0.4)) {
                deck.blocker = .failed(message: AIError.offlineMessage, offline: true)
            }
            return
        }
        deck.isLoading = true
        let dealt: (base: Set<Compound>, cards: [Suggestion])
        do {
            dealt = try await SuggestionEngine.dealDeck(
                craving: cravingText, food: selectedFood, base: baseCompounds,
                accepted: [], rejected: [], note: typedName, profile: ProfileContext.aiProfile()
            )
        } catch {
            guard !Task.isCancelled else { return }
            deck.isLoading = false
            withAnimation(.spring(duration: 0.4)) {
                if case AIError.paywallRequired = error {
                    deck.blocker = .locked
                } else {
                    deck.blocker = .failed(
                        message: AIError.friendlyMessage(for: error, what: "deal the cards"),
                        offline: AIError.isOffline(error) || !NetworkMonitor.shared.isOnline
                    )
                }
            }
            return
        }
        guard !Task.isCancelled else { return }
        deck.isLoading = false
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            deck.load(dealt.cards, base: dealt.base)
        }
        // A plate that already covers all three builders needs zero swipes,
        // so the finished card would otherwise never pick up the AI's
        // teaching-moment summary (that only otherwise fires after a
        // decision). Safe to call unconditionally: a no-op once there are
        // still cards left to swipe.
        await followUpIfNeeded()
    }

    private func decided(added: Bool) {
        if added {
            if currentCompounds.count >= 2 {
                Haptics.success()
            } else {
                Haptics.tap()
            }
        } else {
            Haptics.soft()
        }
        // Flagged the instant it's clear the deck is done, in the same
        // run-loop turn as the decision itself, rather than waiting for the
        // task below to reach it: `Task {}` doesn't start inline, so the
        // finished card could otherwise render one frame with its fallback
        // copy before the fetch had a chance to say it was even in flight.
        if deck.remaining.isEmpty, !deck.chosen.isEmpty, deck.summary == nil,
           currentCompounds.count >= 2 || !deck.canDealMore {
            deck.isSummaryLoading = true
        }
        Task { await followUpIfNeeded() }
    }

    /// The stop rule: two of the three builders make a complete combo, the
    /// third is a bonus the deck still offers when it has cards for it, but
    /// never something worth a network round trip to chase. Another deck
    /// only gets dealt when the last ran out short of even that (the deck
    /// model caps how many), otherwise fetch the AI's teaching summary
    /// once the deck is truly done. A "wrap it up" button never blocks on
    /// either, this only ever adds to what's already showing.
    private func followUpIfNeeded() async {
        guard deck.remaining.isEmpty, !deck.isLoading else { return }
        let complete = currentCompounds.count >= 2
        if !complete, deck.canDealMore {
            deck.isLoading = true
            let accepted = deck.chosen.map(\.boost.name)
            let rejected = deck.decisions.filter { !$0.added }.map(\.suggestion.boost.name)
            // A follow-up deck that can't be dealt is not the end of the
            // world: the swipes so far still stand, so the deck wraps up
            // on them rather than showing an error over a plate that's
            // already better. The one exception is the gate saying no,
            // which locks the deck like anywhere else.
            var cards: [Suggestion] = []
            do {
                cards = try await SuggestionEngine.dealDeck(
                    craving: cravingText, food: selectedFood, base: resolvedBase,
                    accepted: accepted, rejected: rejected, note: typedName, profile: ProfileContext.aiProfile()
                ).cards
            } catch {
                if case AIError.paywallRequired = error, deck.chosen.isEmpty {
                    deck.isLoading = false
                    withAnimation(.spring(duration: 0.4)) { deck.blocker = .locked }
                    return
                }
            }
            deck.isLoading = false
            guard !cards.isEmpty else {
                await fetchSummaryIfNeeded()
                return
            }
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) { deck.appendDealt(cards) }
        } else {
            await fetchSummaryIfNeeded()
        }
    }

    private func fetchSummaryIfNeeded() async {
        // Not also gated on `!deck.isSummaryLoading`: `decided(added:)` may
        // already have set it, synchronously, the moment the deck ended —
        // gating on it here too would just make this call a no-op forever,
        // since nothing else would ever flip it back off.
        guard deck.summary == nil else { return }
        deck.isSummaryLoading = true
        deck.summary = await SuggestionEngine.summary(
            craving: cravingText, accepted: deck.chosen.map(\.boost.name),
            compoundsCovered: currentCompounds, note: typedName, profile: ProfileContext.aiProfile()
        )
        deck.isSummaryLoading = false
        await offerSubscriptionIfLoopSpent()
    }

    /// The summary is the payoff: the craving read, the deck swiped, the
    /// whole thing landed. If that was the one free loop, this is where the
    /// paywall belongs — on the good news, not on an error screen the next
    /// time they open the app.
    ///
    /// The beat before it is deliberate. Covering the summary the instant
    /// it renders would ask people to buy something they haven't been shown.
    private func offerSubscriptionIfLoopSpent() async {
        await SubscriptionStore.shared.refreshGateState()
        guard SubscriptionStore.shared.needsSubscription else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        PaywallCenter.shared.offerAfterFreeLoop()
    }

    private func save() {
        guard !saved else { return }
        saved = true
        let meal = Meal(
            name: mealName.isEmpty ? "Something tasty" : mealName,
            emoji: mealEmoji,
            context: nil,
            compounds: currentCompounds,
            boosts: chosenBoosts.map(\.name),
            photoData: snappedImage?.jpegData(compressionQuality: 0.8)
        )
        modelContext.insert(meal)
        try? modelContext.save()
        Haptics.success()
        dismiss()
        onSaved?()
    }
}

private extension String {
    /// "chocolate chip cookies" → "Chocolate chip cookies", for a name
    /// the AI wrote in lowercase that now leads a field.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
