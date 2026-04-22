import SwiftUI

struct ComposerScreen: View {
    @Bindable var model: BalabolkaAppModel
    @State private var showingSettings = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                editor
                controls
                if let progress = model.generationProgress {
                    GenerationProgressPanel(progress: progress)
                }
                presets

                if let record = model.activeRecord {
                    VideoPreviewCard(
                        title: record.title,
                        subtitle: "\(record.presetSummary) • \(record.voiceName) • \(record.modelName)",
                        videoURL: model.resolvedVideoURL(for: record),
                        envelope: record.waveformEnvelope
                    )

                    GenerationExportPanel(model: model, record: record)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("BALABOLKA")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("toolbar.settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsScreen(settingsStore: model.settingsStore, selectedVoiceName: $model.selectedVoiceName)
        }
        .alert("Ошибка", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Мобильная balabolka для сильного TTS-видеопотока.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Text("Текст, expressive preset, прокси-вызов Gemini 3.1 Flash TTS, локальная сборка квадратного видео 720×720 и история прошлых генераций.")
                .font(.subheadline)
                .foregroundStyle(AppTheme.secondaryInk)
        }
        .padding(.top, 4)
    }

    private var editor: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Название генерации", text: $model.generationTitle)
                    .font(.headline)
                    .accessibilityIdentifier("composer.title")

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.composerText)
                        .frame(minHeight: 220)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityIdentifier("composer.text")

                    if model.composerText.isEmpty {
                        Text("Вставь текст, который нужно превратить в озвученный квадратный ролик.")
                            .foregroundStyle(AppTheme.secondaryInk)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Long-form лимит приложения")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.secondaryInk)
                        Spacer()
                        Text(
                            "\(model.sourceTextCharacterCount.formatted(.number.grouping(.automatic))) / \(BalabolkaLimits.longFormSourceTextMaxCharacters.formatted(.number.grouping(.automatic)))"
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(model.isOverSourceTextLimit ? .red : AppTheme.secondaryInk)
                    }

                    Text("Официальный лимит `gemini-3.1-flash-tts-preview`: \(BalabolkaLimits.officialTokenDescription) на один TTS-вызов. BALABOLKA автоматически режет длинный текст на части: один backend-запрос ограничен \(BalabolkaLimits.proxyRequestMaxDescription), а весь текущий mobile long-form режим — \(BalabolkaLimits.longFormSourceTextMaxDescription).")
                        .font(.caption)
                        .foregroundStyle(model.isOverSourceTextLimit ? .red : AppTheme.secondaryInk)

                    if model.requiresLongFormMode {
                        Text("Включён auto-chunking: ожидаемо частей — \(model.estimatedChunkCount). Это дольше обычной генерации, но приложение соберёт один общий ролик локально.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    if model.isOverSourceTextLimit {
                        Text("Сократи текст или разбей стенограмму на несколько генераций. Для ещё более длинных записей нужен отдельный batch/job режим.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private var controls: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Голос")
                        .font(.headline)
                    Spacer()
                    Picker("Voice", selection: $model.selectedVoiceName) {
                        ForEach(GeminiVoice.allCases) { voice in
                            Text("\(voice.rawValue) · \(voice.descriptor)").tag(voice)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("composer.voice")
                }

                Toggle(isOn: Binding(
                    get: { model.isCombineModeEnabled },
                    set: { model.setCombineMode($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Комбинировать expressive-режимы")
                            .font(.headline)
                        Text("Можно смешать до трёх режимов. Preprocessor сам распределит теги и сценические указания по тексту.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                .tint(AppTheme.accent)
                .accessibilityIdentifier("composer.combineMode")

                if model.isCombineModeEnabled {
                    Picker("Combine mode", selection: $model.selectedCombineMode) {
                        ForEach(ExpressiveCombineMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("composer.combineModePicker")
                }

                Button {
                    model.generate()
                } label: {
                    HStack {
                        if model.isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(model.isGenerating ? progressLabel : "Сгенерировать видео")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canGenerate)
                .accessibilityIdentifier("composer.generate")
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expressive режимы")
                    .font(.title3.weight(.bold))
                Text(model.isCombineModeEnabled ? "Выбрано: \(model.selectedPresetSummary)" : "Активный режим: \(model.selectedPreset.title)")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ExpressivePreset.all) { preset in
                    Button {
                        model.togglePreset(preset.id)
                        if model.selectedVoiceName == model.settingsStore.current.defaultVoice {
                            model.selectedVoiceName = preset.recommendedVoice
                        }
                    } label: {
                        ExpressiveCardView(
                            preset: preset,
                            isSelected: model.selectedPresetIDs.contains(preset.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("preset.\(preset.id.rawValue)")
                }
            }
        }
    }
}

private extension ComposerScreen {
    var progressLabel: String {
        if let progress = model.generationProgress {
            return "\(progress.stage.title) · \(progress.percentText)"
        }

        return "Генерирую"
    }
}

private struct SettingsScreen: View {
    @Bindable var settingsStore: SettingsStore
    @Binding var selectedVoiceName: GeminiVoice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $settingsStore.current.proxyBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("settings.proxyBaseURL")
                    SecureField("Bearer token (legacy / advanced)", text: $settingsStore.current.bearerToken)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("settings.bearerToken")
                }

                Section("Default voice") {
                    Picker("Voice", selection: $settingsStore.current.defaultVoice) {
                        ForEach(GeminiVoice.allCases) { voice in
                            Text("\(voice.rawValue) · \(voice.descriptor)").tag(voice)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        selectedVoiceName = settingsStore.current.defaultVoice
                        dismiss()
                    }
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
    }
}
