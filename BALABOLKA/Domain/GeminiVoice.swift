//
//  GeminiVoice.swift
//  BALABOLKA
//
//  Created by Codex on 4/20/26.
//

import Foundation

enum GeminiVoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case zephyr = "Zephyr"
    case puck = "Puck"
    case charon = "Charon"
    case kore = "Kore"
    case fenrir = "Fenrir"
    case leda = "Leda"
    case orus = "Orus"
    case aoede = "Aoede"
    case callirrhoe = "Callirrhoe"
    case autonoe = "Autonoe"
    case enceladus = "Enceladus"
    case iapetus = "Iapetus"
    case umbriel = "Umbriel"
    case algieba = "Algieba"
    case despina = "Despina"
    case erinome = "Erinome"
    case algenib = "Algenib"
    case rasalgethi = "Rasalgethi"
    case laomedeia = "Laomedeia"
    case achernar = "Achernar"
    case alnilam = "Alnilam"
    case schedar = "Schedar"
    case gacrux = "Gacrux"
    case pulcherrima = "Pulcherrima"
    case achird = "Achird"
    case zubenelgenubi = "Zubenelgenubi"
    case vindemiatrix = "Vindemiatrix"
    case sadachbia = "Sadachbia"
    case sadaltager = "Sadaltager"
    case sulafat = "Sulafat"

    var id: String { rawValue }

    var descriptor: String {
        switch self {
        case .zephyr, .autonoe:
            return "яркий"
        case .puck, .laomedeia:
            return "живой"
        case .charon, .rasalgethi:
            return "информативный"
        case .kore, .orus, .alnilam:
            return "собранный"
        case .fenrir:
            return "возбуждённый"
        case .leda:
            return "молодой"
        case .aoede:
            return "лёгкий"
        case .callirrhoe, .umbriel:
            return "спокойный"
        case .enceladus:
            return "дыхательный"
        case .iapetus, .erinome:
            return "чёткий"
        case .algieba, .despina:
            return "гладкий"
        case .algenib:
            return "шероховатый"
        case .achernar:
            return "мягкий"
        case .schedar:
            return "ровный"
        case .gacrux:
            return "зрелый"
        case .pulcherrima:
            return "напористый"
        case .achird:
            return "дружелюбный"
        case .zubenelgenubi:
            return "разговорный"
        case .vindemiatrix:
            return "деликатный"
        case .sadachbia:
            return "энергичный"
        case .sadaltager:
            return "знающий"
        case .sulafat:
            return "тёплый"
        }
    }

    var summary: String {
        switch self {
        case .zephyr:
            return "Светлый и лёгкий тон для открытой подачи."
        case .puck:
            return "Бодрая манера, хорошо держит улыбку в голосе."
        case .charon:
            return "Ровная информативная подача без лишней драматизации."
        case .kore:
            return "Жёстче держит опору, подходит для напряжённой речи."
        case .fenrir:
            return "Импульсивный голос с хорошей атакой начала фразы."
        case .leda:
            return "Молодой тембр с более светлой верхней серединой."
        case .orus:
            return "Собранный и плотный голос для уверенной дикции."
        case .aoede:
            return "Воздушная и лёгкая подача."
        case .callirrhoe:
            return "Ненапряжённый голос для мягкой разговорной манеры."
        case .autonoe:
            return "Ещё один яркий вариант для ясной нейтральной речи."
        case .enceladus:
            return "Более дыхательный тембр, полезен для шёпота и усталости."
        case .iapetus:
            return "Чистая артикуляция и хорошая читаемость текста."
        case .umbriel:
            return "Невозмутимый расслабленный голос."
        case .algieba:
            return "Плавный, сглаженный тембр без резких углов."
        case .despina:
            return "Мягко скользящая подача."
        case .erinome:
            return "Ясный и аккуратный голос."
        case .algenib:
            return "Сухая шероховатость для хрипоты и кашля."
        case .rasalgethi:
            return "Сильнее звучит как диктор или рассказчик."
        case .laomedeia:
            return "Подвижный голос для улыбки, смеха и лёгкой иронии."
        case .achernar:
            return "Мягкий, тихий и деликатный тембр."
        case .alnilam:
            return "Плотная опора и более жёсткая подача."
        case .schedar:
            return "Стабильный нейтральный голос."
        case .gacrux:
            return "Более взрослый тембр для тяжёлых эмоций."
        case .pulcherrima:
            return "Напористый голос с передней атакой."
        case .achird:
            return "Дружелюбная и естественная разговорная манера."
        case .zubenelgenubi:
            return "Казуальный голос для сухого сарказма."
        case .vindemiatrix:
            return "Нежная подача, полезна для тихих и печальных режимов."
        case .sadachbia:
            return "Очень живая подача с выраженной энергией."
        case .sadaltager:
            return "Спокойный уверенный тембр с ощущением компетентности."
        case .sulafat:
            return "Тёплая нейтральная подача для мягкого baseline."
        }
    }
}
