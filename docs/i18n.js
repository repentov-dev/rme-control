// RME Control — language switching. English is the source; Russian and German
// are chosen automatically from the browser and can be switched by hand.
(function () {
  var dict = {
    en: {
      "meta.title": "RME Control — TotalMix in the menu bar",
      "meta.desc": "Open-source menu bar app for RME audio interfaces: TotalMix control, Room EQ, headphone presets and a room calibration wizard.",
      "nav.new": "What's new", "nav.screens": "Screens",
      "nav.features": "Features", "nav.install": "Install", "nav.download": "Download 4.0",
      "hero.title": "TotalMix in the menu bar",
      "hero.sub": "Open-source control for RME interfaces — now with Room EQ, headphone presets and a room calibration wizard.",
      "hero.download": "Download 4.0", "hero.source": "Read the source",
      "hero.note": "Global OSC, TotalMix 2.1 or newer. macOS 14+, Apple Silicon and Intel.",
      "new.eyebrow": "Version 4.0",
      "new.title": "New in version 4.0",
      "new.eq.kicker": "Room EQ",
      "new.eq.title": "Fully carried over from TotalMix",
      "new.eq.text": "Nine bands on every output, with Mix and Crossfeed right inside the Room EQ window.",
      "new.hp.kicker": "Headphones",
      "new.hp.title": "Presets for popular headphones",
      "new.hp.text": "A large library of presets for the most popular models, built from AutoEQ and independent measurements.",
      "new.stat.brands": "brands",
      "new.stat.models": "models",
      "new.engine.kicker": "Correction engine",
      "new.engine.title": "Powered by roomeq",
      "new.engine.text": "Sweeps are captured by sotf-capture and the correction is calculated by roomeq — both by Pierre Aubert and contributors; roomeq continues the AutoEQ project by Jaakko Pasanen. Save your own calibration presets; microphone calibration files are supported.",
      "screens.eyebrow": "Screens", "screens.title": "What the app looks like",
      "shot.app.name": "RME Control",
      "shot.app": "The mixer in the menu bar, the channel EQ, the compressor and the level window.",
      "shot.product.name": "Measure and Room EQ",
      "shot.product": "Setup, the measurement, the result and the Room EQ that receives it.",
      "features.eyebrow": "Features", "features.title": "Everything in the app",
      "feat.out.title": "Outputs",
      "feat.out.volume": "Volume keys", "feat.out.volume.v": "Any output, 1–10 dB a step",
      "feat.out.dim": "Dim and mute", "feat.out.dim.v": "On the Mac mute key, either one",
      "feat.out.mono": "Mono", "feat.out.mono.v": "Shift Cmd M",
      "feat.out.speaker": "Speaker B", "feat.out.speaker.v": "The second pair of monitors",
      "feat.out.room": "Room EQ", "feat.out.room.v": "Nine bands, delay, crossfeed and Mix",
      "feat.in.title": "Inputs",
      "feat.in.phantom": "Phantom power", "feat.in.phantom.v": "+48V on any number of channels",
      "feat.in.inst": "Instrument mode", "feat.in.inst.v": "Inst per channel",
      "feat.in.eq": "EQ", "feat.in.eq.v": "Four bands a channel",
      "feat.in.comp": "Compressor", "feat.in.comp.v": "Threshold, ratio, attack, release, gain",
      "feat.in.meters": "Meters", "feat.in.meters.v": "Input, gain reduction and output",
      "feat.app.title": "The app",
      "feat.app.levels": "Levels", "feat.app.levels.v": "Always on top, clipping in red",
      "feat.app.presets": "Presets", "feat.app.presets.v": "Channels, Room EQ and calibration",
      "feat.app.shortcuts": "Shortcuts", "feat.app.shortcuts.v": "Every one can be reassigned",
      "feat.app.languages": "Languages", "feat.app.languages.v": "14",
      "feat.app.remote": "Remote", "feat.app.remote.v": "Web control from a phone",
      "install.title": "Install in four steps",
      "install.one": "Download", "install.one.b": "and open it.",
      "install.two": "Not notarized: allow it once under Privacy and Security. The installer clears the quarantine flag.",
      "install.three": "If macOS still refuses to open it, take the app out of quarantine:",
      "install.four": "Grant Accessibility in the same pane so the volume keys reach TotalMix.",
      "install.download": "Download the installer", "install.build": "Build it yourself",
      "tm.eyebrow": "TotalMix", "tm.title": "Set up TotalMix",
      "tm.summary": "Global OSC in TotalMix FX 2.1+: host 127.0.0.1, ports 7001 and 9001, Compatibility (Mode) Global OSC, then Send Status, Send level data, Peak hold and Send all data on start.",
      "specs.eyebrow": "Specs", "specs.title": "On the label",
      "specs.version": "Version", "specs.system": "System", "specs.system.v": "macOS 14 Sonoma or newer",
      "specs.arch": "Architecture", "specs.arch.v": "arm64 and x86_64, one universal build",
      "specs.languages": "Interface", "specs.languages.v": "14 languages",
      "specs.license": "License", "specs.source": "Source",
      "foot.note": "A menu bar controller for TotalMix FX, written in Swift and shipped as source.",
      "foot.repo": "Repository", "foot.releases": "Releases", "foot.license": "MIT license",
      "foot.legal": "RME, TotalMix and the RME logo are trademarks of RME Audio AG. This is an independent tool, not affiliated with or endorsed by RME Audio.",
      "foot.credits": "Measurement: sotf-capture. Correction: roomeq, continuing AutoEQ by Jaakko Pasanen. Both by Pierre Aubert and contributors, GPL-3.0."
    },
    ru: {
      "meta.title": "RME Control — TotalMix в строке меню",
      "meta.desc": "Открытое приложение в строке меню для интерфейсов RME: управление TotalMix, Room EQ, пресеты наушников и мастер калибровки комнаты.",
      "nav.new": "Что нового", "nav.screens": "Экраны",
      "nav.features": "Возможности", "nav.install": "Установка", "nav.download": "Скачать 4.0",
      "hero.title": "TotalMix в строке меню",
      "hero.sub": "Открытое управление интерфейсами RME — теперь с Room EQ, пресетами наушников и мастером калибровки комнаты.",
      "hero.download": "Скачать 4.0", "hero.source": "Исходный код",
      "hero.note": "Global OSC, TotalMix 2.1 или новее. macOS 14+, Apple Silicon и Intel.",
      "new.eyebrow": "Версия 4.0",
      "new.title": "Что нового в версии 4.0",
      "new.eq.kicker": "Room EQ",
      "new.eq.title": "Полностью перенесён из TotalMix",
      "new.eq.text": "Девять полос на каждый выход, а ручки Mix и Crossfeed теперь прямо в окне Room EQ.",
      "new.hp.kicker": "Наушники",
      "new.hp.title": "Пресеты для популярных наушников",
      "new.hp.text": "Большая библиотека пресетов для самых популярных моделей — на основе AutoEQ и независимых измерений.",
      "new.stat.brands": "брендов",
      "new.stat.models": "моделей",
      "new.engine.kicker": "Движок коррекции",
      "new.engine.title": "На движке roomeq",
      "new.engine.text": "Замер выполняет sotf-capture, коррекцию считает roomeq — оба от Pierre Aubert и участников проекта; roomeq продолжает AutoEQ Яакко Пасанена. Свои пресеты калибровки сохраняются, калибровочные файлы микрофонов поддерживаются.",
      "screens.eyebrow": "Экраны", "screens.title": "Как это выглядит",
      "shot.app.name": "RME Control",
      "shot.app": "Пульт в строке меню, канальный EQ, компрессор и окно уровней.",
      "shot.product.name": "Замер и Room EQ",
      "shot.product": "Настройка, замер, результат и Room EQ, в который он попадает.",
      "features.eyebrow": "Возможности", "features.title": "Всё в приложении",
      "feat.out.title": "Выходы",
      "feat.out.volume": "Клавиши громкости", "feat.out.volume.v": "Любой выход, шаг 1–10 дБ",
      "feat.out.dim": "Dim и mute", "feat.out.dim.v": "На клавише mute Mac, любой из них",
      "feat.out.mono": "Mono", "feat.out.mono.v": "Shift Cmd M",
      "feat.out.speaker": "Speaker B", "feat.out.speaker.v": "Вторая пара мониторов",
      "feat.out.room": "Room EQ", "feat.out.room.v": "Девять полос, задержка, crossfeed и Mix",
      "feat.in.title": "Входы",
      "feat.in.phantom": "Фантомное питание", "feat.in.phantom.v": "+48V на любом числе каналов",
      "feat.in.inst": "Режим инструмента", "feat.in.inst.v": "Inst на канал",
      "feat.in.eq": "EQ", "feat.in.eq.v": "Четыре полосы на канал",
      "feat.in.comp": "Компрессор", "feat.in.comp.v": "Порог, ratio, атака, release, gain",
      "feat.in.meters": "Индикаторы", "feat.in.meters.v": "Вход, снижение усиления и выход",
      "feat.app.title": "Приложение",
      "feat.app.levels": "Уровни", "feat.app.levels.v": "Всегда сверху, клиппинг красным",
      "feat.app.presets": "Пресеты", "feat.app.presets.v": "Каналы, Room EQ и калибровка",
      "feat.app.shortcuts": "Горячие клавиши", "feat.app.shortcuts.v": "Любую можно переназначить",
      "feat.app.languages": "Языки", "feat.app.languages.v": "14",
      "feat.app.remote": "Пульт", "feat.app.remote.v": "Управление с телефона",
      "install.title": "Установка за четыре шага",
      "install.one": "Скачайте", "install.one.b": "и откройте.",
      "install.two": "Приложение не нотаризовано: разрешите его один раз в «Конфиденциальность и безопасность». Установщик снимает карантин.",
      "install.three": "Если macOS всё равно не открывает, снимите карантин вручную:",
      "install.four": "Разрешите Accessibility в том же разделе, чтобы клавиши громкости доходили до TotalMix.",
      "install.download": "Скачать установщик", "install.build": "Собрать самому",
      "tm.eyebrow": "TotalMix", "tm.title": "Настройка TotalMix",
      "tm.summary": "Global OSC в TotalMix FX 2.1+: host 127.0.0.1, порты 7001 и 9001, Compatibility (Mode) Global OSC, затем Send Status, Send level data, Peak hold и Send all data on start.",
      "specs.eyebrow": "Характеристики", "specs.title": "На этикетке",
      "specs.version": "Версия", "specs.system": "Система", "specs.system.v": "macOS 14 Sonoma или новее",
      "specs.arch": "Архитектура", "specs.arch.v": "arm64 и x86_64, одна универсальная сборка",
      "specs.languages": "Интерфейс", "specs.languages.v": "14 языков",
      "specs.license": "Лицензия", "specs.source": "Исходники",
      "foot.note": "Пульт для TotalMix FX в строке меню, на Swift и с открытым исходным кодом.",
      "foot.repo": "Репозиторий", "foot.releases": "Релизы", "foot.license": "Лицензия MIT",
      "foot.legal": "RME, TotalMix и логотип RME — товарные знаки RME Audio AG. Это независимый инструмент, не связанный с RME Audio.",
      "foot.credits": "Замер: sotf-capture. Коррекция: roomeq, продолжение AutoEQ Яакко Пасанена. Авторы — Pierre Aubert и участники, GPL-3.0."
    },
    de: {
      "meta.title": "RME Control — TotalMix in der Menüleiste",
      "meta.desc": "Open-Source-Menüleisten-App für RME-Interfaces: TotalMix-Steuerung, Room EQ, Kopfhörer-Presets und ein Raumkalibrierungs-Assistent.",
      "nav.new": "Neu", "nav.screens": "Bildschirme",
      "nav.features": "Funktionen", "nav.install": "Installation", "nav.download": "Laden 4.0",
      "hero.title": "TotalMix in der Menüleiste",
      "hero.sub": "Open-Source-Steuerung für RME-Interfaces — jetzt mit Room EQ, Kopfhörer-Presets und Raumkalibrierung.",
      "hero.download": "Laden 4.0", "hero.source": "Quellcode",
      "hero.note": "Global OSC, TotalMix 2.1 oder neuer. macOS 14+, Apple Silicon und Intel.",
      "new.eyebrow": "Version 4.0",
      "new.title": "Neu in Version 4.0",
      "new.eq.kicker": "Room EQ",
      "new.eq.title": "Vollständig aus TotalMix übernommen",
      "new.eq.text": "Neun Bänder an jedem Ausgang, mit Mix und Crossfeed direkt im Room-EQ-Fenster.",
      "new.hp.kicker": "Kopfhörer",
      "new.hp.title": "Presets für beliebte Kopfhörer",
      "new.hp.text": "Eine große Preset-Bibliothek für die beliebtesten Modelle, auf Basis von AutoEQ und unabhängigen Messungen.",
      "new.stat.brands": "Marken",
      "new.stat.models": "Modelle",
      "new.engine.kicker": "Korrektur-Engine",
      "new.engine.title": "Angetrieben von roomeq",
      "new.engine.text": "Die Sweeps nimmt sotf-capture auf, die Korrektur berechnet roomeq — beide von Pierre Aubert und Mitwirkenden; roomeq führt das AutoEQ-Projekt von Jaakko Pasanen fort. Eigene Kalibrier-Presets und Mikrofon-Kalibrierdateien werden unterstützt.",
      "screens.eyebrow": "Bildschirme", "screens.title": "So sieht die App aus",
      "shot.app.name": "RME Control",
      "shot.app": "Der Mixer in der Menüleiste, der Kanal-EQ, der Kompressor und das Pegelfenster.",
      "shot.product.name": "Messung und Room EQ",
      "shot.product": "Setup, die Messung, das Ergebnis und der Room EQ, der es aufnimmt.",
      "features.eyebrow": "Funktionen", "features.title": "Alles in der App",
      "feat.out.title": "Ausgänge",
      "feat.out.volume": "Lautstärketasten", "feat.out.volume.v": "Jeder Ausgang, 1–10 dB pro Schritt",
      "feat.out.dim": "Dim und Mute", "feat.out.dim.v": "Auf der Mute-Taste, beides",
      "feat.out.mono": "Mono", "feat.out.mono.v": "Shift Cmd M",
      "feat.out.speaker": "Speaker B", "feat.out.speaker.v": "Das zweite Monitorpaar",
      "feat.out.room": "Room EQ", "feat.out.room.v": "Neun Bänder, Delay, Crossfeed und Mix",
      "feat.in.title": "Eingänge",
      "feat.in.phantom": "Phantomspeisung", "feat.in.phantom.v": "+48V auf beliebig vielen Kanälen",
      "feat.in.inst": "Instrumentenmodus", "feat.in.inst.v": "Inst pro Kanal",
      "feat.in.eq": "EQ", "feat.in.eq.v": "Vier Bänder pro Kanal",
      "feat.in.comp": "Kompressor", "feat.in.comp.v": "Threshold, Ratio, Attack, Release, Gain",
      "feat.in.meters": "Pegelanzeigen", "feat.in.meters.v": "Eingang, Gain Reduction und Ausgang",
      "feat.app.title": "Die App",
      "feat.app.levels": "Pegel", "feat.app.levels.v": "Immer im Vordergrund, Clipping rot",
      "feat.app.presets": "Presets", "feat.app.presets.v": "Kanäle, Room EQ und Kalibrierung",
      "feat.app.shortcuts": "Tastenkürzel", "feat.app.shortcuts.v": "Alle neu belegbar",
      "feat.app.languages": "Sprachen", "feat.app.languages.v": "14",
      "feat.app.remote": "Fernsteuerung", "feat.app.remote.v": "Web-Steuerung vom Telefon",
      "install.title": "Installation in vier Schritten",
      "install.one": "Laden Sie", "install.one.b": "herunter und öffnen Sie es.",
      "install.two": "Nicht notarisiert: einmal unter Datenschutz und Sicherheit erlauben. Der Installer entfernt das Quarantäne-Flag.",
      "install.three": "Wenn macOS es weiterhin blockiert, die App aus der Quarantäne nehmen:",
      "install.four": "Accessibility im selben Bereich erlauben, damit die Lautstärketasten TotalMix erreichen.",
      "install.download": "Installer laden", "install.build": "Selbst bauen",
      "tm.eyebrow": "TotalMix", "tm.title": "TotalMix einrichten",
      "tm.summary": "Global OSC in TotalMix FX 2.1+: Host 127.0.0.1, Ports 7001 und 9001, Compatibility (Mode) Global OSC, dann Send Status, Send level data, Peak hold und Send all data on start.",
      "specs.eyebrow": "Daten", "specs.title": "Auf dem Etikett",
      "specs.version": "Version", "specs.system": "System", "specs.system.v": "macOS 14 Sonoma oder neuer",
      "specs.arch": "Architektur", "specs.arch.v": "arm64 und x86_64, ein Universal-Build",
      "specs.languages": "Oberfläche", "specs.languages.v": "14 Sprachen",
      "specs.license": "Lizenz", "specs.source": "Quellcode",
      "foot.note": "Ein Menüleisten-Controller für TotalMix FX, in Swift geschrieben und als Quellcode veröffentlicht.",
      "foot.repo": "Repository", "foot.releases": "Releases", "foot.license": "MIT-Lizenz",
      "foot.legal": "RME, TotalMix und das RME-Logo sind Marken der RME Audio AG. Dies ist ein unabhängiges Werkzeug, nicht mit RME Audio verbunden.",
      "foot.credits": "Messung: sotf-capture. Korrektur: roomeq, Fortführung von AutoEQ von Jaakko Pasanen. Beides von Pierre Aubert und Mitwirkenden, GPL-3.0."
    }
  };

  function pick() {
    try {
      var forced = new URLSearchParams(window.location.search).get("lang");
      if (forced && dict[forced]) return forced;
    } catch (e) {}
    var stored = null;
    try { stored = localStorage.getItem("rme-lang"); } catch (e) {}
    if (stored && dict[stored]) return stored;
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    for (var i = 0; i < list.length; i++) {
      var tag = String(list[i]).toLowerCase();
      if (tag.indexOf("ru") === 0) return "ru";
      if (tag.indexOf("de") === 0) return "de";
    }
    return "en";
  }

  function apply(lang) {
    var d = dict[lang] || dict.en;
    document.documentElement.lang = lang;
    document.title = d["meta.title"];
    var meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute("content", d["meta.desc"]);
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var key = el.getAttribute("data-i18n");
      if (d[key]) el.textContent = d[key];
    });
    document.querySelectorAll(".lang button").forEach(function (b) {
      var on = b.getAttribute("data-lang") === lang;
      b.classList.toggle("is-on", on);
      b.setAttribute("aria-pressed", on ? "true" : "false");
    });
    try { localStorage.setItem("rme-lang", lang); } catch (e) {}
  }

  document.querySelectorAll(".lang button").forEach(function (b) {
    b.addEventListener("click", function () { apply(b.getAttribute("data-lang")); });
  });

  apply(pick());
})();
