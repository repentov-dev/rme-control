// RME Control — language switching. English is the source; Russian and German
// are chosen automatically from the browser and can be switched by hand.
// Every language carries the whole dictionary: text, alt texts, ARIA labels,
// the page title and the meta description.
(function () {
  var dict = {
    en: {
      "meta.title": "RME Control — TotalMix in the menu bar",
      "meta.desc": "Free, open-source macOS menu bar control for RME interfaces: TotalMix volume and output switching, Room EQ, room calibration, headphone presets, input and output processing.",
      "nav.new": "What's new", "nav.screens": "Screens",
      "nav.features": "Features", "nav.install": "Install", "nav.site": "Website", "nav.download": "Download 4.1",
      "nav.sections": "Sections", "nav.language": "Language", "nav.menu": "Menu",
      "hero.title": "TotalMix in the menu bar",
      "hero.sub": "Free, open-source control for TotalMix FX: volume and output switching, Room EQ and calibration, headphone presets — from the menu bar.",
      "hero.download": "Download 4.1", "hero.source": "Read the source", "hero.forum": "RME forum",
      "hero.note": "Global OSC, TotalMix 2.1 or newer. macOS 14+, Apple Silicon and Intel.",
      "new.eyebrow": "Version 4.1",
      "new.title": "New in version 4.1",
      "new.module.kicker": "Measure",
      "new.module.title": "A module you download",
      "new.module.text": "Measure is now a separate module: install it from Settings → Modules.",
      "new.presets.kicker": "Presets",
      "new.presets.title": "The whole app in one preset",
      "new.presets.text": "Presets capture channels, equalizers, dynamics, Room EQ, faders and Control Room buttons and restore all of it. Export to a file, import on another Mac.",
      "new.ux.kicker": "Interface",
      "new.ux.title": "Better equalizer and Room EQ",
      "new.ux.text": "A denser frequency axis with ticks, live readings under the cursor, a compressor/expander switch, and Room EQ redraws about five times faster.",
      "new.expander.kicker": "Dynamics",
      "new.expander.title": "Expander",
      "new.expander.text": "Dynamics switches between compressor and expander, with the matching curve and TotalMix's own expander parameters.",
      "new.measure11.kicker": "Measure 1.1",
      "new.measure11.title": "Measurement engine update",
      "new.measure11.text": "Clear error handling, a smoother measurement flow and an algorithm aligned with the engine author's recommendations.",
      "screens.eyebrow": "Screens", "screens.title": "What the app looks like",
      "shot.app.name": "RME Control",
      "shot.app": "The mixer in the menu bar, the channel EQ, the compressor and the level window.",
      "shot.popover.alt": "RME Control menu bar popover",
      "shot.product.name": "Measure and Room EQ",
      "shot.product": "Setup, the measurement, the result and the Room EQ that receives it.",
      "shot.windows.alt": "RME Control windows",
      "shot.measure.alt": "Measure setup, Room EQ and the measurement result",
      "features.eyebrow": "Features", "features.title": "Everything in the app",
      "features.lead": "RME Control is a free, open-source macOS utility that controls the TotalMix FX mixer for RME audio interfaces straight from the Mac menu bar. It saves you from opening the main app window for everyday settings.",
      "feat.out.kicker": "Outputs",
      "feat.out.title": "Volume, switching and processing",
      "feat.out.text": "Adjust the volume and switch between outputs from the Mac keyboard, toggle Mute, Dim and Mono, and reach the compressor and 3-band EQ on output channels.",
      "feat.eq.kicker": "Room EQ",
      "feat.eq.title": "Room EQ and calibration",
      "feat.eq.text": "A full port of Room EQ from TotalMix for every output, with delay and Crossfeed, plus a room calibration wizard that supports measurement microphone calibration files.",
      "feat.hp.kicker": "Headphones",
      "feat.hp.title": "Headphone presets",
      "feat.hp.text": "A built-in library of EQ curves for 80 headphone models across 25 popular brands.",
      "feat.in.kicker": "Inputs",
      "feat.in.title": "Input settings",
      "feat.in.text": "Quick access to +48V phantom power, Instrument mode (Inst), EQ and compressor on input channels.",
      "feat.more.kicker": "More",
      "feat.more.title": "Levels, presets and the phone",
      "feat.more.text": "Always-on-top level meters, custom presets, customizable keyboard shortcuts and web-based remote control from a phone browser.",
      "install.title": "Install in four steps",
      "install.one": "Download", "install.one.b": "and open it.",
      "install.two": "Not notarized: allow it once under Privacy and Security. The installer clears the quarantine flag.",
      "install.three": "If macOS still refuses to open it, take the app out of quarantine:",
      "install.cmd.copy": "Copy", "install.cmd.copied": "Copied",
      "install.four": "Grant Accessibility in the same pane so the volume keys reach TotalMix.",
      "install.download": "Download the installer", "install.build": "Build it yourself",
      "tm.eyebrow": "TotalMix", "tm.title": "Set up TotalMix",
      "tm.lead": "The app speaks Global OSC. In TotalMix FX 2.1 or newer:",
      "tm.one": "Set the OSC host to 127.0.0.1 and the ports to 7001 and 9001.",
      "tm.two": "Open Options → Mixer Settings → OSC and set Compatibility (Mode) to Global OSC.",
      "tm.three": "Turn on Send Status.",
      "tm.four": "Turn on Send level data.",
      "tm.five": "Turn on Peak hold.",
      "tm.six": "Turn on Send all data on start.",
      "tm.note": "Then open Settings → Connection in RME Control and use the same ports.",
      "specs.eyebrow": "Specs", "specs.title": "On the label",
      "specs.version": "Version", "specs.system": "System", "specs.system.v": "macOS 14 Sonoma or newer",
      "specs.arch": "Architecture", "specs.arch.v": "arm64 and x86_64, one universal build",
      "specs.languages": "Interface", "specs.languages.v": "14 languages",
      "specs.license": "License", "specs.source": "Source",
      "foot.note": "A free, open-source menu bar controller for TotalMix FX, written in Swift.",
      "foot.links": "Elsewhere",
      "foot.repo": "Repository", "foot.releases": "Releases", "foot.license": "MIT license",
      "foot.legal": "RME, TotalMix and the RME logo are trademarks of RME Audio AG. This is an independent tool, not affiliated with or endorsed by RME Audio.",
      "foot.credits": "Calibration engines and headphone data:",
    },
    ru: {
      "meta.title": "RME Control — TotalMix в строке меню",
      "meta.desc": "Бесплатное открытое управление TotalMix для RME из строки меню macOS: громкость и переключение выходов, Room EQ, калибровка комнаты, пресеты наушников, обработка входов и выходов.",
      "nav.new": "Что нового", "nav.screens": "Экраны",
      "nav.features": "Возможности", "nav.install": "Установка", "nav.site": "Мой сайт", "nav.download": "Скачать 4.1",
      "nav.sections": "Разделы", "nav.language": "Язык", "nav.menu": "Меню",
      "hero.title": "TotalMix в строке меню",
      "hero.sub": "Бесплатное открытое управление TotalMix FX: громкость и переключение выходов, Room EQ и калибровка, пресеты наушников — из строки меню.",
      "hero.download": "Скачать 4.1", "hero.source": "Исходный код", "hero.forum": "Форум RME",
      "hero.note": "Global OSC, TotalMix 2.1 или новее. macOS 14+, Apple Silicon и Intel.",
      "new.eyebrow": "Версия 4.1",
      "new.title": "Что нового в версии 4.1",
      "new.module.kicker": "Замер",
      "new.module.title": "Модуль, который вы скачиваете",
      "new.module.text": "Measure — теперь отдельный модуль: ставится из Настроек → Модули.",
      "new.presets.kicker": "Пресеты",
      "new.presets.title": "Всё приложение в одном пресете",
      "new.presets.text": "Пресет сохраняет каналы, эквалайзеры, динамику, Room EQ, фейдеры и кнопки Control Room — и возвращает всё это. Экспорт в файл, импорт на другом Mac.",
      "new.ux.kicker": "Интерфейс",
      "new.ux.title": "Улучшенные эквалайзер и Room EQ",
      "new.ux.text": "Плотная ось частот с насечками, считывание под курсором, переключатель компрессор/экспандер, Room EQ перерисовывается примерно в пять раз быстрее.",
      "new.expander.kicker": "Динамика",
      "new.expander.title": "Экспандер",
      "new.expander.text": "Dynamics переключается между компрессором и экспандером: своя кривая и родные поля экспандера из TotalMix.",
      "new.measure11.kicker": "Measure 1.1",
      "new.measure11.title": "Обновление движка замера",
      "new.measure11.text": "Понятная обработка ошибок, более плавный сценарий замера и алгоритм измерения, приведённый к рекомендациям автора движка.",
      "screens.eyebrow": "Экраны", "screens.title": "Как это выглядит",
      "shot.app.name": "RME Control",
      "shot.app": "Пульт в строке меню, канальный EQ, компрессор и окно уровней.",
      "shot.popover.alt": "Поповер RME Control в строке меню",
      "shot.product.name": "Замер и Room EQ",
      "shot.product": "Настройка, замер, результат и Room EQ, в который он попадает.",
      "shot.windows.alt": "Окна RME Control",
      "shot.measure.alt": "Настройка замера, Room EQ и результат измерения",
      "features.eyebrow": "Возможности", "features.title": "Всё в приложении",
      "features.lead": "RME Control — бесплатная утилита с открытым исходным кодом для macOS, которая позволяет управлять микшером TotalMix FX для аудиоинтерфейсов RME прямо из строки меню Mac. Она избавляет от необходимости постоянно открывать основное окно программы для базовых настроек.",
      "feat.out.kicker": "Выходы",
      "feat.out.title": "Громкость, переключение и обработка",
      "feat.out.text": "Громкость и быстрое переключение между выходами с клавиатуры Mac, режимы Mute, Dim и Mono, а также компрессор и 3-полосный эквалайзер на выходных каналах.",
      "feat.eq.kicker": "Room EQ",
      "feat.eq.title": "Room EQ и калибровка",
      "feat.eq.text": "Room EQ полностью перенесён из TotalMix для каждого выхода, с задержкой и Crossfeed, плюс мастер калибровки акустики с поддержкой файлов калибровки измерительных микрофонов.",
      "feat.hp.kicker": "Наушники",
      "feat.hp.title": "Пресеты для наушников",
      "feat.hp.text": "Встроенная библиотека кривых эквализации для 80 моделей наушников от 25 популярных брендов.",
      "feat.in.kicker": "Входы",
      "feat.in.title": "Настройка входов",
      "feat.in.text": "Быстрый доступ к фантомному питанию +48V, режиму инструмента (Inst), эквалайзеру и компрессору на входных каналах.",
      "feat.more.kicker": "Ещё",
      "feat.more.title": "Уровни, пресеты и телефон",
      "feat.more.text": "Индикаторы уровней поверх всех окон, пользовательские пресеты, настраиваемые горячие клавиши и удалённое управление через браузер телефона.",
      "install.title": "Установка за четыре шага",
      "install.one": "Скачайте", "install.one.b": "и откройте.",
      "install.two": "Приложение не нотаризовано: разрешите его один раз в «Конфиденциальность и безопасность». Установщик снимает карантин.",
      "install.three": "Если macOS всё равно не открывает, снимите карантин вручную:",
      "install.cmd.copy": "Скопировать", "install.cmd.copied": "Скопировано",
      "install.four": "Разрешите «Универсальный доступ» в том же разделе, чтобы клавиши громкости доходили до TotalMix.",
      "install.download": "Скачать установщик", "install.build": "Собрать самому",
      "tm.eyebrow": "TotalMix", "tm.title": "Настройка TotalMix",
      "tm.lead": "Приложение говорит по Global OSC. В TotalMix FX 2.1 или новее:",
      "tm.one": "Укажите OSC host 127.0.0.1 и порты 7001 и 9001.",
      "tm.two": "Откройте Options → Mixer Settings → OSC и поставьте Compatibility (Mode): Global OSC.",
      "tm.three": "Включите Send Status.",
      "tm.four": "Включите Send level data.",
      "tm.five": "Включите Peak hold.",
      "tm.six": "Включите Send all data on start.",
      "tm.note": "Затем откройте Settings → Connection в RME Control и укажите те же порты.",
      "specs.eyebrow": "Характеристики", "specs.title": "На этикетке",
      "specs.version": "Версия", "specs.system": "Система", "specs.system.v": "macOS 14 Sonoma или новее",
      "specs.arch": "Архитектура", "specs.arch.v": "arm64 и x86_64, одна универсальная сборка",
      "specs.languages": "Интерфейс", "specs.languages.v": "14 языков",
      "specs.license": "Лицензия", "specs.source": "Исходники",
      "foot.note": "Бесплатный пульт для TotalMix FX в строке меню, написан на Swift с открытым исходным кодом.",
      "foot.links": "Другие ссылки",
      "foot.repo": "Репозиторий", "foot.releases": "Релизы", "foot.license": "Лицензия MIT",
      "foot.legal": "RME, TotalMix и логотип RME — товарные знаки RME Audio AG. Это независимый инструмент, не связанный с RME Audio.",
      "foot.credits": "Движки калибровки и база наушников:",
    },
    de: {
      "meta.title": "RME Control — TotalMix in der Menüleiste",
      "meta.desc": "Kostenlose Open-Source-Steuerung für TotalMix FX aus der macOS-Menüleiste: Lautstärke und Ausgangswechsel, Room EQ, Raumkalibrierung, Kopfhörer-Presets, Ein- und Ausgangsbearbeitung.",
      "nav.new": "Neuerungen", "nav.screens": "Bildschirme",
      "nav.features": "Funktionen", "nav.install": "Installation", "nav.site": "Meine Seite", "nav.download": "4.1 laden",
      "nav.sections": "Bereiche", "nav.language": "Sprache", "nav.menu": "Menü",
      "hero.title": "TotalMix in der Menüleiste",
      "hero.sub": "Kostenlose Open-Source-Steuerung für TotalMix FX: Lautstärke und Ausgangswechsel, Room EQ und Kalibrierung, Kopfhörer-Presets — aus der Menüleiste.",
      "hero.download": "4.1 laden", "hero.source": "Quellcode", "hero.forum": "RME-Forum",
      "hero.note": "Global OSC, TotalMix 2.1 oder neuer. macOS 14+, Apple Silicon und Intel.",
      "new.eyebrow": "Version 4.1",
      "new.title": "Neu in Version 4.1",
      "new.module.kicker": "Messung",
      "new.module.title": "Ein Modul zum Herunterladen",
      "new.module.text": "Measure ist jetzt ein eigenes Modul: Installieren Sie es unter Einstellungen → Module.",
      "new.presets.kicker": "Presets",
      "new.presets.title": "Die ganze App in einem Preset",
      "new.presets.text": "Ein Preset erfasst Kanäle, Equalizer, Dynamik, Room EQ, Fader und Control-Room-Tasten — und stellt alles wieder her. In eine Datei exportieren, auf einem anderen Mac importieren.",
      "new.ux.kicker": "Oberfläche",
      "new.ux.title": "Besserer Equalizer und Room EQ",
      "new.ux.text": "Eine dichtere Frequenzachse mit Markierungen, Live-Werte unter dem Cursor, ein Umschalter für Kompressor/Expander — Room EQ zeichnet etwa fünfmal schneller neu.",
      "new.expander.kicker": "Dynamik",
      "new.expander.title": "Expander",
      "new.expander.text": "Dynamik schaltet zwischen Kompressor und Expander um, mit passender Kurve und den Expander-Parametern aus TotalMix.",
      "new.measure11.kicker": "Measure 1.1",
      "new.measure11.title": "Update der Mess-Engine",
      "new.measure11.text": "Klare Fehlerbehandlung, ein ruhigerer Messablauf und ein Algorithmus nach den Empfehlungen des Engine-Autors.",
      "screens.eyebrow": "Bildschirme", "screens.title": "So sieht die App aus",
      "shot.app.name": "RME Control",
      "shot.app": "Der Mixer in der Menüleiste, der Kanal-EQ, der Kompressor und das Pegelfenster.",
      "shot.popover.alt": "RME-Control-Popover in der Menüleiste",
      "shot.product.name": "Messung und Room EQ",
      "shot.product": "Setup, die Messung, das Ergebnis und der Room EQ, der es aufnimmt.",
      "shot.windows.alt": "RME-Control-Fenster",
      "shot.measure.alt": "Mess-Setup, Room EQ und das Messergebnis",
      "features.eyebrow": "Funktionen", "features.title": "Alles in der App",
      "features.lead": "RME Control ist ein kostenloses Open-Source-Werkzeug für macOS, das den TotalMix-FX-Mixer für RME-Interfaces direkt aus der Menüleiste steuert. Für alltägliche Einstellungen muss das Hauptfenster nicht mehr geöffnet werden.",
      "feat.out.kicker": "Ausgänge",
      "feat.out.title": "Lautstärke, Umschalten und Bearbeitung",
      "feat.out.text": "Lautstärke und schneller Ausgangswechsel über die Mac-Tastatur, Mute, Dim und Mono sowie Kompressor und 3-Band-EQ auf den Ausgangskanälen.",
      "feat.eq.kicker": "Room EQ",
      "feat.eq.title": "Room EQ und Kalibrierung",
      "feat.eq.text": "Room EQ vollständig aus TotalMix übernommen, für jeden Ausgang mit Delay und Crossfeed, plus ein Raumkalibrierungs-Assistent mit Unterstützung für Mikrofon-Kalibrierdateien.",
      "feat.hp.kicker": "Kopfhörer",
      "feat.hp.title": "Kopfhörer-Presets",
      "feat.hp.text": "Eine eingebaute Bibliothek von EQ-Kurven für 80 Kopfhörermodelle von 25 beliebten Marken.",
      "feat.in.kicker": "Eingänge",
      "feat.in.title": "Eingangseinstellungen",
      "feat.in.text": "Schneller Zugriff auf +48V Phantomspeisung, Instrumentenmodus (Inst), EQ und Kompressor auf den Eingangskanälen.",
      "feat.more.kicker": "Mehr",
      "feat.more.title": "Pegel, Presets und das Telefon",
      "feat.more.text": "Immer sichtbare Pegelanzeigen, eigene Presets, frei belegbare Tastenkürzel und Fernsteuerung über den Browser am Telefon.",
      "install.title": "Installation in vier Schritten",
      "install.one": "Laden Sie", "install.one.b": "herunter und öffnen Sie es.",
      "install.two": "Nicht notarisiert: einmal unter Datenschutz und Sicherheit erlauben. Der Installer entfernt das Quarantäne-Flag.",
      "install.three": "Wenn macOS es weiterhin blockiert, die App aus der Quarantäne nehmen:",
      "install.cmd.copy": "Kopieren", "install.cmd.copied": "Kopiert",
      "install.four": "Erlauben Sie Bedienungshilfen im selben Bereich, damit die Lautstärketasten TotalMix erreichen.",
      "install.download": "Installer laden", "install.build": "Selbst bauen",
      "tm.eyebrow": "TotalMix", "tm.title": "TotalMix einrichten",
      "tm.lead": "Die App spricht Global OSC. In TotalMix FX 2.1 oder neuer:",
      "tm.one": "OSC-Host auf 127.0.0.1 und die Ports auf 7001 und 9001 setzen.",
      "tm.two": "Options → Mixer Settings → OSC öffnen und Compatibility (Mode) auf Global OSC setzen.",
      "tm.three": "Send Status einschalten.",
      "tm.four": "Send level data einschalten.",
      "tm.five": "Peak hold einschalten.",
      "tm.six": "Send all data on start einschalten.",
      "tm.note": "Dann in RME Control Settings → Connection öffnen und dieselben Ports eintragen.",
      "specs.eyebrow": "Technische Daten", "specs.title": "Auf dem Etikett",
      "specs.version": "Version", "specs.system": "System", "specs.system.v": "macOS 14 Sonoma oder neuer",
      "specs.arch": "Architektur", "specs.arch.v": "arm64 und x86_64, ein Universal-Build",
      "specs.languages": "Oberfläche", "specs.languages.v": "14 Sprachen",
      "specs.license": "Lizenz", "specs.source": "Quellcode",
      "foot.note": "Ein kostenloser Open-Source-Menüleisten-Controller für TotalMix FX, in Swift geschrieben.",
      "foot.links": "Weitere Links",
      "foot.repo": "Repository", "foot.releases": "Releases", "foot.license": "MIT-Lizenz",
      "foot.legal": "RME, TotalMix und das RME-Logo sind Marken der RME Audio AG. Dies ist ein unabhängiges Werkzeug, nicht mit RME Audio verbunden.",
      "foot.credits": "Kalibrierungs-Engines und Kopfhörer-Datenbank:",
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
    // Other scripts need the words of the active language to repaint state
    // ("Copied") without keeping their own copy of the dictionary.
    window.rmeI18n = { lang: lang, t: function (key) { return d[key] || ""; } };
    document.documentElement.lang = lang;
    document.title = d["meta.title"];
    var meta = document.querySelector('meta[name="description"]');
    if (meta) meta.setAttribute("content", d["meta.desc"]);
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var key = el.getAttribute("data-i18n");
      if (d[key]) el.textContent = d[key];
    });
    // Alt texts and ARIA labels are copy as well: data-i18n-alt,
    // data-i18n-aria-label and data-i18n-title hold the key for the attribute.
    ["alt", "aria-label", "title"].forEach(function (attr) {
      document.querySelectorAll("[data-i18n-" + attr + "]").forEach(function (el) {
        var key = el.getAttribute("data-i18n-" + attr);
        if (d[key]) el.setAttribute(attr, d[key]);
      });
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
