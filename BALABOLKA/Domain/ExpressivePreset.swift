//
//  ExpressivePreset.swift
//  BALABOLKA
//
//  Created by Codex on 4/20/26.
//

import Foundation

struct StageDirectionCue: Codable, Hashable, Sendable {
    enum Placement: String, Codable, Sendable {
        case openingBoundary
        case sentenceBoundary
        case paragraphBoundary
        case closingBoundary
    }

    var placement: Placement
    var instruction: String
}

struct ExpressivePromptPackage: Codable, Hashable, Sendable {
    var presetID: ExpressivePreset.ID
    var presetTitle: String
    var chosenVoice: GeminiVoice
    var alternativeVoices: [GeminiVoice]
    var intensity: Double
    var audioProfile: String
    var scene: String
    var directorNotes: [String]
    var stageDirections: [StageDirectionCue]
    var transcript: String

    var renderedPrompt: String {
        let directorBlock = directorNotes.map { "- \($0)" }.joined(separator: "\n")
        let stageBlock = stageDirections.isEmpty
            ? "- No extra non-verbal insertions unless they are explicitly requested in the director notes."
            : stageDirections.map { "- \($0.placement.rawValue): \($0.instruction)" }.joined(separator: "\n")

        return """
        Generate a single-speaker TTS performance.

        Audio Profile:
        \(audioProfile)

        Scene:
        \(scene)

        Director's Notes:
        \(directorBlock)

        Stage Directions:
        \(stageBlock)

        Voice:
        - Primary voice: \(chosenVoice.rawValue) (\(chosenVoice.descriptor))
        - Alternatives: \(alternativeVoices.map(\.rawValue).joined(separator: ", "))
        - Intensity target: \(String(format: "%.2f", intensity)) on a 0.0 to 1.0 scale.

        Transcript:
        Recite the transcript exactly in the original language. Do not paraphrase, summarize, censor, translate, add commentary, or change wording.
        \"\"\"
        \(transcript)
        \"\"\"
        """
    }
}

struct ExpressivePreset: Codable, Hashable, Identifiable, Sendable {
    enum ID: String, CaseIterable, Codable, Identifiable, Sendable {
        case quiet
        case whisper
        case laugh
        case cry
        case cough
        case hoarse
        case sarcasm
        case anger
        case tired
        case heavyBreathing

        var id: String { rawValue }
    }

    struct SpeechShape: Codable, Hashable, Sendable {
        var volume: String
        var tempo: String
        var breathiness: String
        var texture: String
        var articulation: String
        var pauseCadence: String
    }

    var id: ID
    var title: String
    var shortDescription: String
    var speechShape: SpeechShape
    var recommendedVoices: [GeminiVoice]
    var defaultIntensity: Double
    var supportedIntensityRange: ClosedRange<Double>
    var audioProfileTemplate: String
    var sceneTemplate: String
    var baselineDirectorNotes: [String]
    var avoidNotes: [String]
    var stageDirections: [StageDirectionCue]

    var identity: ID { id }

    func normalizedIntensity(_ intensity: Double?) -> Double {
        let requested = intensity ?? defaultIntensity
        return min(max(requested, supportedIntensityRange.lowerBound), supportedIntensityRange.upperBound)
    }

    func makePrompt(
        for text: String,
        intensity: Double? = nil,
        selectedVoice: GeminiVoice? = nil
    ) -> ExpressivePromptPackage {
        let clampedIntensity = normalizedIntensity(intensity)
        let chosenVoice = selectedVoice ?? recommendedVoices.first ?? .sulafat
        let directorNotes = baselineDirectorNotes
            + dynamicDirectorNotes(for: clampedIntensity)
            + avoidNotes.map { "Avoid: \($0)" }

        return ExpressivePromptPackage(
            presetID: id,
            presetTitle: title,
            chosenVoice: chosenVoice,
            alternativeVoices: recommendedVoices,
            intensity: clampedIntensity,
            audioProfile: audioProfileText(for: clampedIntensity, chosenVoice: chosenVoice),
            scene: sceneText(for: clampedIntensity),
            directorNotes: directorNotes,
            stageDirections: stageDirections,
            transcript: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func audioProfileText(for intensity: Double, chosenVoice: GeminiVoice) -> String {
        let calibration = intensityCalibration(for: intensity)
        return "\(audioProfileTemplate) Use \(chosenVoice.rawValue) as the starting timbre reference. \(calibration.audioProfileSuffix)"
    }

    private func sceneText(for intensity: Double) -> String {
        let calibration = intensityCalibration(for: intensity)
        return "\(sceneTemplate) \(calibration.sceneSuffix)"
    }

    private func dynamicDirectorNotes(for intensity: Double) -> [String] {
        let calibration = intensityCalibration(for: intensity)
        return calibration.directorNotes
    }

    private func intensityCalibration(for intensity: Double) -> IntensityCalibration {
        switch id {
        case .quiet:
            if intensity < 0.35 {
                return .init(
                    audioProfileSuffix: "Keep the performer intimate, restrained and almost private, but still fully intelligible.",
                    sceneSuffix: "The delivery should feel close-mic, controlled and emotionally contained.",
                    directorNotes: [
                        "Stay near the microphone with low physical effort.",
                        "Keep consonants clear even though overall loudness is reduced.",
                        "Use soft phrase endings instead of fading into inaudibility."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Keep the performer intimate, but with enough pressure to hold clarity through longer phrases.",
                sceneSuffix: "The delivery should feel like deliberate low-volume speech, not fear or whispering.",
                directorNotes: [
                    "Maintain a quiet voice with stable support under the line.",
                    "Add slight warmth so the result does not feel emotionally flat.",
                    "Keep pauses smooth and deliberate."
                ]
            )

        case .whisper:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Use a light airy whisper with stable intelligibility and minimal throat noise.",
                    sceneSuffix: "The room is silent, and every syllable feels close to the listener's ear.",
                    directorNotes: [
                        "Whisper rather than softly speaking with full voicing.",
                        "Keep the consonants crisp enough that the words remain understandable.",
                        "Avoid theatrical horror tropes unless the text itself demands them."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use a pronounced whisper with more breath flow and slightly more friction in the consonants.",
                sceneSuffix: "The atmosphere is tense and intimate, with audible air movement on phrase starts.",
                directorNotes: [
                    "Push breathiness further while keeping the transcript readable.",
                    "Allow short natural breath pickups between clauses.",
                    "Do not let the whisper collapse into pure noise."
                ]
            )

        case .laugh:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Color the speech with a smiling, amused resonance rather than constant overt laughter.",
                    sceneSuffix: "The performer is genuinely entertained and suppressing a grin while speaking.",
                    directorNotes: [
                        "Let the smile be audible inside vowels and phrase endings.",
                        "Use tiny amused releases at safe boundaries, not inside every sentence.",
                        "Keep the transcript exact."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use audible laugh energy and light chuckles at boundaries while preserving the words.",
                sceneSuffix: "The performer keeps breaking into laughter but remains capable of finishing the line.",
                directorNotes: [
                    "Allow short chuckles before or after strong sentence boundaries.",
                    "The laugh must support the text instead of overwhelming it.",
                    "Do not convert the delivery into pure giggling."
                ]
            )

        case .cry:
            if intensity < 0.5 {
                return .init(
                    audioProfileSuffix: "Shape the voice as fragile and tearful, with occasional instability in breath support.",
                    sceneSuffix: "The speaker is trying to stay composed but emotion leaks into the line.",
                    directorNotes: [
                        "Use a dampened, trembling line with light breaks in support.",
                        "Small voice cracks are acceptable at emotionally loaded boundaries.",
                        "Keep words understandable."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use a more broken, sobbing edge while preserving sentence intelligibility.",
                sceneSuffix: "The speaker is actively crying and fighting through breath disruptions to finish the text.",
                directorNotes: [
                    "Permit audible catches of breath and more obvious instability.",
                    "Add brief sob-like interruptions only at boundaries.",
                    "Do not paraphrase or shorten the text."
                ]
            )

        case .cough:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Use a dry throat and restrained cough behavior, as if the speaker is trying not to interrupt themselves.",
                    sceneSuffix: "The speaker has irritation in the throat but still aims for a clean take.",
                    directorNotes: [
                        "Place cough artifacts very sparingly.",
                        "Prefer one light clearing of the throat around a sentence boundary rather than repeated interruptions.",
                        "Return quickly to stable articulation after each cough."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use a rougher throat state with more audible recovery between clauses.",
                sceneSuffix: "The speaker is repeatedly managing throat irritation while forcing the take through.",
                directorNotes: [
                    "Allow short cough or throat-clear events at natural boundaries only.",
                    "Keep the body of the transcript intact and understandable.",
                    "Do not overdo non-verbal events beyond what is needed to sell the effect."
                ]
            )

        case .hoarse:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Use a textured, lightly scraped timbre without losing basic vocal support.",
                    sceneSuffix: "The voice sounds worn down and dry, but still functional.",
                    directorNotes: [
                        "Keep the hoarseness consistent across the line.",
                        "Use reduced brightness and slight rasp instead of whispering.",
                        "Avoid dramatic coughing unless the transcript demands it."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Push the rasp further, as if the voice is overused and strained after a long day.",
                sceneSuffix: "The speaker sounds vocally taxed, with friction at the onset of phrases.",
                directorNotes: [
                    "Increase grain and roughness while preserving intelligibility.",
                    "Support the low mids so the sound remains present.",
                    "Do not turn the line into a whisper."
                ]
            )

        case .sarcasm:
            if intensity < 0.4 {
                return .init(
                    audioProfileSuffix: "Use a dry, underplayed irony with calm control and small timing shifts.",
                    sceneSuffix: "The speaker is more amused than hostile and does not need to perform for the room.",
                    directorNotes: [
                        "Use deadpan timing and slightly delayed emphasis.",
                        "Let the irony live in the rhythm, not in exaggerated acting.",
                        "Keep the line readable as natural speech."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use more pointed irony and clearer contrast between literal words and implied meaning.",
                sceneSuffix: "The speaker enjoys the sting of the line and leans into it with controlled bite.",
                directorNotes: [
                    "Add sharper phrase turns and more obvious undercutting emphasis.",
                    "Keep the delivery cold, not cartoonishly snide.",
                    "Do not add extra verbal ad-libs."
                ]
            )

        case .anger:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Use restrained anger with compressed energy and controlled jaw tension.",
                    sceneSuffix: "The speaker is angry, but still keeping the line under control.",
                    directorNotes: [
                        "Favor clipped consonants and shorter pauses.",
                        "Do not shout unless the transcript already implies it.",
                        "Keep the threat or frustration inside the line."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use a more forceful, heated line with sharper attacks and stronger pressure.",
                sceneSuffix: "The speaker is close to snapping and channels that energy into each phrase.",
                directorNotes: [
                    "Drive phrase openings harder.",
                    "Use narrowed vowels and more aggressive stop consonants.",
                    "Maintain intelligibility instead of turning into raw yelling."
                ]
            )

        case .tired:
            if intensity < 0.45 {
                return .init(
                    audioProfileSuffix: "Use low energy, softened attacks and a sense of depleted motivation.",
                    sceneSuffix: "The speaker is physically present but emotionally running on reserve.",
                    directorNotes: [
                        "Let phrase starts arrive a fraction late, as if energy is low.",
                        "Keep breath support thin but stable.",
                        "Do not make the line unintelligible or sleepy to the point of collapse."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use heavier fatigue with audible drag, sagging posture and slower recovery between phrases.",
                sceneSuffix: "The speaker is exhausted and barely pushing through the take.",
                directorNotes: [
                    "Increase the drag between clauses.",
                    "Permit short exhale-like releases around boundaries.",
                    "Keep the exact text intact."
                ]
            )

        case .heavyBreathing:
            if intensity < 0.5 {
                return .init(
                    audioProfileSuffix: "Use noticeable breath pressure and mild exertion while still prioritizing readability.",
                    sceneSuffix: "The speaker has just exerted themselves and is talking through elevated breathing.",
                    directorNotes: [
                        "Break phrases where natural breaths would occur.",
                        "Make inhalations audible but brief.",
                        "Avoid turning the result into panic unless the text itself suggests it."
                    ]
                )
            }
            return .init(
                audioProfileSuffix: "Use stronger exertion and more pronounced inhale-recover cycles between clauses.",
                sceneSuffix: "The speaker sounds winded and works around heavy breathing to get the words out.",
                directorNotes: [
                    "Keep breaths clearly audible at boundaries.",
                    "Protect the transcript from being swallowed by breath noise.",
                    "Do not add extra words or improvised reactions."
                ]
            )
        }
    }

    static let all: [ExpressivePreset] = ID.allCases.map(\.preset)
}

private struct IntensityCalibration {
    var audioProfileSuffix: String
    var sceneSuffix: String
    var directorNotes: [String]
}

extension ExpressivePreset.ID {
    var proxyIdentifier: String {
        switch self {
        case .heavyBreathing:
            return "heavy_breathing"
        default:
            return rawValue
        }
    }

    var preset: ExpressivePreset {
        switch self {
        case .quiet:
            return ExpressivePreset(
                id: self,
                title: "Тихо",
                shortDescription: "Низкая громкость без потери дикции.",
                speechShape: .init(
                    volume: "пониженная",
                    tempo: "ровный",
                    breathiness: "лёгкая",
                    texture: "чистая",
                    articulation: "аккуратная",
                    pauseCadence: "мягкие паузы"
                ),
                recommendedVoices: [.achernar, .vindemiatrix, .sulafat],
                defaultIntensity: 0.38,
                supportedIntensityRange: 0.15 ... 0.8,
                audioProfileTemplate: "A close-mic, intimate performer speaking below conversational volume while staying emotionally readable.",
                sceneTemplate: "A clean studio with almost no room sound and a listener who is very close.",
                baselineDirectorNotes: [
                    "The delivery should sound intentionally quiet, not distant.",
                    "Preserve exact wording and clean articulation."
                ],
                avoidNotes: [
                    "slipping into whisper mode unless explicitly desired",
                    "washing out phrase endings"
                ],
                stageDirections: []
            )

        case .whisper:
            return ExpressivePreset(
                id: self,
                title: "Шёпот",
                shortDescription: "Настоящий шёпот с контролируемой разборчивостью.",
                speechShape: .init(
                    volume: "очень низкая",
                    tempo: "слегка медленнее нормы",
                    breathiness: "высокая",
                    texture: "воздушная",
                    articulation: "сухая и точная",
                    pauseCadence: "короткие дыхательные паузы"
                ),
                recommendedVoices: [.enceladus, .achernar, .vindemiatrix],
                defaultIntensity: 0.48,
                supportedIntensityRange: 0.2 ... 0.95,
                audioProfileTemplate: "A whispering performer with a stable close-mic technique and careful diction.",
                sceneTemplate: "A nearly silent room where the listener can hear air movement and lip proximity.",
                baselineDirectorNotes: [
                    "Whisper the text rather than narrating about whispering.",
                    "Keep the transcript precise and unchanged."
                ],
                avoidNotes: [
                    "full voiced speech masquerading as whisper",
                    "horror-cliche acting if the source text is neutral"
                ],
                stageDirections: [
                    .init(placement: .sentenceBoundary, instruction: "Allow subtle breaths between longer clauses if needed for realism.")
                ]
            )

        case .laugh:
            return ExpressivePreset(
                id: self,
                title: "Смех",
                shortDescription: "Улыбка и смех в подаче без развала текста.",
                speechShape: .init(
                    volume: "средняя",
                    tempo: "подвижный",
                    breathiness: "средняя",
                    texture: "улыбающаяся",
                    articulation: "живая",
                    pauseCadence: "игривые отскоки"
                ),
                recommendedVoices: [.puck, .laomedeia, .sadachbia],
                defaultIntensity: 0.46,
                supportedIntensityRange: 0.15 ... 0.9,
                audioProfileTemplate: "A speaker whose amusement colors the resonance and timing of the line.",
                sceneTemplate: "A conversational setting where the performer is genuinely entertained by the words.",
                baselineDirectorNotes: [
                    "Treat the transcript as exact speech content.",
                    "Keep laughter as texture or short boundary events, not as constant interruption."
                ],
                avoidNotes: [
                    "continuous giggling over every word",
                    "inventing extra comedy lines"
                ],
                stageDirections: [
                    .init(placement: .openingBoundary, instruction: "A very short amused release is allowed if intensity is high enough."),
                    .init(placement: .closingBoundary, instruction: "A small trailing chuckle is acceptable only when it does not obscure the final words.")
                ]
            )

        case .cry:
            return ExpressivePreset(
                id: self,
                title: "Плач",
                shortDescription: "Слёзы и надлом, но текст остаётся понятным.",
                speechShape: .init(
                    volume: "пониженная или средняя",
                    tempo: "ломающийся",
                    breathiness: "средне-высокая",
                    texture: "надломленная",
                    articulation: "бережная",
                    pauseCadence: "эмоциональные сбои"
                ),
                recommendedVoices: [.achernar, .enceladus, .gacrux],
                defaultIntensity: 0.58,
                supportedIntensityRange: 0.25 ... 0.95,
                audioProfileTemplate: "A tearful performer whose emotional control is slipping but not gone.",
                sceneTemplate: "A private emotional moment where the speaker is trying to finish the line through tears.",
                baselineDirectorNotes: [
                    "Use crying texture without rewriting the transcript.",
                    "Protect key words and sentence meaning."
                ],
                avoidNotes: [
                    "melodramatic wailing that destroys intelligibility",
                    "adding spoken descriptions of crying"
                ],
                stageDirections: [
                    .init(placement: .sentenceBoundary, instruction: "Short unstable breaths or tiny sob catches may appear at natural emotional boundaries.")
                ]
            )

        case .cough:
            return ExpressivePreset(
                id: self,
                title: "Кашель",
                shortDescription: "Раздражённое горло и редкие кашлевые врезки.",
                speechShape: .init(
                    volume: "средняя",
                    tempo: "слегка прерывистый",
                    breathiness: "средняя",
                    texture: "сухая",
                    articulation: "быстро восстанавливается",
                    pauseCadence: "редкие перебои"
                ),
                recommendedVoices: [.algenib, .gacrux, .enceladus],
                defaultIntensity: 0.42,
                supportedIntensityRange: 0.1 ... 0.8,
                audioProfileTemplate: "A speaker with throat irritation who still attempts a clean spoken take.",
                sceneTemplate: "A dry recording environment that reveals throat strain and recovery.",
                baselineDirectorNotes: [
                    "Cough behavior must stay sparse and useful.",
                    "The performance should still sound like someone trying to get through the text."
                ],
                avoidNotes: [
                    "turning the take into repeated cough noises",
                    "covering important words with non-verbal sounds"
                ],
                stageDirections: [
                    .init(placement: .sentenceBoundary, instruction: "If needed, place a single short cough or throat-clear only at a natural clause break.")
                ]
            )

        case .hoarse:
            return ExpressivePreset(
                id: self,
                title: "Хрипота",
                shortDescription: "Сухая шероховатость без ухода в шёпот.",
                speechShape: .init(
                    volume: "средняя",
                    tempo: "ровный или слегка тяжёлый",
                    breathiness: "средняя",
                    texture: "зернистая",
                    articulation: "чёткая, но тёртая",
                    pauseCadence: "ровные тяжёлые паузы"
                ),
                recommendedVoices: [.algenib, .gacrux, .orus],
                defaultIntensity: 0.47,
                supportedIntensityRange: 0.2 ... 0.85,
                audioProfileTemplate: "A voice with rasp, dryness and reduced gloss, as if it has been overused.",
                sceneTemplate: "The performer is recording with a worn throat but enough support to finish the read.",
                baselineDirectorNotes: [
                    "Keep hoarseness consistent instead of isolated on one word.",
                    "Favor grain and dryness over airy whispering."
                ],
                avoidNotes: [
                    "random coughing unless explicitly needed",
                    "losing the core pitch center completely"
                ],
                stageDirections: []
            )

        case .sarcasm:
            return ExpressivePreset(
                id: self,
                title: "Сарказм",
                shortDescription: "Сухая ирония через тайминг и подачу.",
                speechShape: .init(
                    volume: "средняя",
                    tempo: "контролируемый с микропаузами",
                    breathiness: "низкая",
                    texture: "сухая и прохладная",
                    articulation: "точная",
                    pauseCadence: "смысловые задержки"
                ),
                recommendedVoices: [.zubenelgenubi, .charon, .kore],
                defaultIntensity: 0.43,
                supportedIntensityRange: 0.1 ... 0.85,
                audioProfileTemplate: "A dry, intelligent speaker who uses timing and emphasis to undercut the literal meaning.",
                sceneTemplate: "A direct conversational exchange where the performer does not need to oversell the joke.",
                baselineDirectorNotes: [
                    "Keep the irony mostly in cadence and emphasis.",
                    "The speaker should sound in control, not manic."
                ],
                avoidNotes: [
                    "cartoon villain energy",
                    "adding new sarcastic comments outside the transcript"
                ],
                stageDirections: []
            )

        case .anger:
            return ExpressivePreset(
                id: self,
                title: "Злость",
                shortDescription: "Собранная или горячая злость без срыва в крик.",
                speechShape: .init(
                    volume: "средняя или повышенная",
                    tempo: "напряжённый",
                    breathiness: "низкая",
                    texture: "жёсткая",
                    articulation: "ударная",
                    pauseCadence: "сжатые паузы"
                ),
                recommendedVoices: [.kore, .alnilam, .fenrir],
                defaultIntensity: 0.52,
                supportedIntensityRange: 0.2 ... 0.95,
                audioProfileTemplate: "A tense, angry speaker with compressed energy and firm phrase attacks.",
                sceneTemplate: "An emotionally heated moment where the speaker is pushing anger through the text.",
                baselineDirectorNotes: [
                    "Channel anger into pressure, attack and clipped timing.",
                    "Do not invent profanity or new lines."
                ],
                avoidNotes: [
                    "constant screaming",
                    "slurring due to excessive force"
                ],
                stageDirections: []
            )

        case .tired:
            return ExpressivePreset(
                id: self,
                title: "Усталость",
                shortDescription: "Низкая энергия, опавшая опора и усталый ритм.",
                speechShape: .init(
                    volume: "пониженная",
                    tempo: "замедленный",
                    breathiness: "средняя",
                    texture: "обессиленная",
                    articulation: "смягчённая",
                    pauseCadence: "вялые паузы"
                ),
                recommendedVoices: [.enceladus, .achernar, .umbriel],
                defaultIntensity: 0.5,
                supportedIntensityRange: 0.2 ... 0.9,
                audioProfileTemplate: "A fatigued speaker with reduced physical energy and slower recoveries between phrases.",
                sceneTemplate: "Late-night or end-of-day exhaustion in a close recording environment.",
                baselineDirectorNotes: [
                    "The listener should hear depleted energy rather than sadness by default.",
                    "Let the tiredness live in attack, pace and breath management."
                ],
                avoidNotes: [
                    "falling asleep mid-line",
                    "turning fatigue into a whisper unless selected separately"
                ],
                stageDirections: [
                    .init(placement: .sentenceBoundary, instruction: "A soft exhale-like release can appear at long boundaries if it does not mask the words.")
                ]
            )

        case .heavyBreathing:
            return ExpressivePreset(
                id: self,
                title: "Тяжёлое дыхание",
                shortDescription: "Слышимые вдохи и выдохи на фоне сохранённого текста.",
                speechShape: .init(
                    volume: "средняя",
                    tempo: "фразовый, с дыхательными разрывами",
                    breathiness: "высокая",
                    texture: "запыхавшаяся",
                    articulation: "удерживаемая под нагрузкой",
                    pauseCadence: "дыхательные границы"
                ),
                recommendedVoices: [.enceladus, .fenrir, .algenib],
                defaultIntensity: 0.6,
                supportedIntensityRange: 0.25 ... 0.98,
                audioProfileTemplate: "A winded speaker whose breath is part of the performance, but not more important than the words.",
                sceneTemplate: "The speaker has just exerted themselves and is talking while recovering oxygen.",
                baselineDirectorNotes: [
                    "Breaths should sound physical and placed, not randomly sprayed over the transcript.",
                    "Protect word intelligibility."
                ],
                avoidNotes: [
                    "panic hyperventilation unless the text clearly asks for it",
                    "drowning consonants under breath noise"
                ],
                stageDirections: [
                    .init(placement: .sentenceBoundary, instruction: "Allow clearly audible inhale or recovery breath at natural phrase boundaries."),
                    .init(placement: .paragraphBoundary, instruction: "A longer recovery breath is acceptable between larger thought units.")
                ]
            )
        }
    }
}
