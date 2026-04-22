import SwiftUI

struct LibraryScreen: View {
    @Bindable var model: BalabolkaAppModel

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            List {
                if model.history.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Пока пусто")
                                .font(.headline)
                            Text("После первой генерации здесь появится библиотека квадратных роликов, и каждый можно будет заново открыть, проиграть и расшарить.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(model.history) { record in
                        NavigationLink {
                            GenerationDetailScreen(model: model, record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.title)
                                            .font(.headline)
                                        Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Text(record.presetSummary)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.accentSoft)
                                        .clipShape(Capsule())
                                }

                                WaveformThumbnailView(samples: record.waveformEnvelope)
                                    .frame(height: 88)

                                Text(record.preparedTranscript)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.secondaryInk)
                                    .lineLimit(3)
                            }
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("history.row.content")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("history.row")
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("История")
        .accessibilityIdentifier("library.list")
    }

    private func delete(_ offsets: IndexSet) {
        model.deleteHistory(at: offsets)
    }
}

private struct GenerationDetailScreen: View {
    @Bindable var model: BalabolkaAppModel
    let record: GenerationRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VideoPreviewCard(
                    title: record.title,
                    subtitle: "\(record.presetSummary) • \(record.voiceName)",
                    videoURL: model.resolvedVideoURL(for: record),
                    envelope: record.waveformEnvelope
                )

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Подготовленный transcript")
                            .font(.headline)
                        Text(record.preparedTranscript)
                            .foregroundStyle(AppTheme.ink)
                    }
                }

                Panel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Исходный текст")
                            .font(.headline)
                        Text(record.sourceText)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }

                GenerationExportPanel(model: model, record: record)
                    .accessibilityIdentifier("detail.export")

                Button {
                    model.select(record: record)
                } label: {
                    Label("Открыть в редакторе", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("detail.reopen")
            }
            .padding(18)
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
