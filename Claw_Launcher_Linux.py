#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nome do Script  : Claw_Launcher_Linux.py
Descrição       : Dashboard WebApp nativo KDE com perfil isolado
Autor           : Rafael Batista
Versão          : 1.0.2
Compatibilidade : Fedora Kinoite / COSMIC (Atomic)
"""

import os
import sys
import json
from pathlib import Path

# Antes do QApplication — flags Chromium para Wayland
os.environ.setdefault(
    "QTWEBENGINE_CHROMIUM_FLAGS",
    " ".join([
        "--ozone-platform-hint=auto",
        "--enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer",
        "--js-flags=--max-old-space-size=256",   # V8 heap: 256 MB por renderer
        "--renderer-process-limit=1",            # máximo 1 processo renderer
        "--disable-dev-shm-usage",               # usa /tmp em vez de /dev/shm
        "--disable-gpu-shader-disk-cache",       # sem cache de shaders em disco
        "--disk-cache-size=52428800",            # cache HTTP máx 50 MB
        "--media-cache-size=52428800",           # cache mídia máx 50 MB
    ])
)

USER_HOME   = Path.home()
APP_ID      = "OneNote"
APP_NAME    = "OneNote"
URL         = "https://onenote.cloud.microsoft/pt-br/"
CONFIG_DIR  = USER_HOME / ".local" / "share" / APP_ID
CONFIG_FILE = CONFIG_DIR / "config.json"

try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QToolBar, QLabel,
        QComboBox, QLineEdit, QProgressBar, QWidget, QSizePolicy
    )
    from PyQt6.QtGui import QKeySequence, QIcon, QAction
    from PyQt6.QtWebEngineWidgets import QWebEngineView
    from PyQt6.QtWebEngineCore import (
        QWebEngineProfile, QWebEnginePage,
        QWebEngineDownloadRequest, QWebEngineSettings
    )
    from PyQt6.QtCore import QUrl, Qt
except ImportError as e:
    print(f"\n\033[1;31m[ERRO DE DEPENDÊNCIA]\033[0m: {e}")
    sys.exit(1)

TRANSLATIONS: dict[str, dict[str, str]] = {
    "pt-br": {
        "back": "⬅ Voltar", "forward": "➡ Avançar",
        "refresh": "🔄 Recarregar", "home": "🏠 Início",
        "lang_label": "Idioma:", "starting": "Iniciando",
        "zoom_in": "🔍+", "zoom_out": "🔍-",
        "fullscreen": "⛶ Tela Cheia",
        "loading": "Carregando...", "ready": "Pronto",
        "download_saved": "📥 Salvo em Downloads",
        "url_placeholder": "Digite uma URL e pressione Enter",
    },
    "en": {
        "back": "⬅ Back", "forward": "➡ Forward",
        "refresh": "🔄 Refresh", "home": "🏠 Home",
        "lang_label": "Language:", "starting": "Starting",
        "zoom_in": "🔍+", "zoom_out": "🔍-",
        "fullscreen": "⛶ Fullscreen",
        "loading": "Loading...", "ready": "Ready",
        "download_saved": "📥 Saved to Downloads",
        "url_placeholder": "Type a URL and press Enter",
    }
}

def load_config() -> dict:
    if not CONFIG_FILE.exists():
        return {"lang": "pt-br", "zoom": 1.0}
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        print(f"\033[1;33m[AVISO]\033[0m Config corrompida ({e}), usando padrão.")
        return {"lang": "pt-br", "zoom": 1.0}

def save_config(config: dict) -> bool:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=2, ensure_ascii=False)
        return True
    except OSError as e:
        print(f"\033[1;31m[ERRO]\033[0m Falha ao salvar config: {e}")
        return False

class ClawPage(QWebEnginePage):
    def __init__(self, profile: QWebEngineProfile, parent=None) -> None:
        super().__init__(profile, parent)
        self._profile = profile
        # Fecha popup quando JS chama window.close() (OAuth, login flows)
        self.windowCloseRequested.connect(self._on_window_close_requested)

    def _on_window_close_requested(self) -> None:
        """Fecha o popup quando o site chama window.close()."""
        view = self.view()
        if view:
            view.close()

    def createWindow(self, web_window_type) -> "ClawPage":
        """
        Comportamento padrão de navegador:
        - Mesmo perfil (cookies/sessão compartilhados)
        - Site controla tamanho via window.open() params
        - window.close() fecha o popup automaticamente
        """
        popup = QWebEngineView()
        popup.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        popup_page = ClawPage(self._profile, popup)
        popup.setPage(popup_page)

        parent_win = QApplication.activeWindow()
        if parent_win:
            popup.setParent(parent_win, Qt.WindowType.Window)

        popup.setWindowFlags(
            Qt.WindowType.Window
            | Qt.WindowType.WindowCloseButtonHint
            | Qt.WindowType.WindowMinMaxButtonsHint
        )

        # Tamanho padrão — site pode sobrescrever via geometryChangeRequested
        popup.resize(1024, 768)

        # Deixa o site controlar o tamanho (window.open com width/height)
        popup_page.geometryChangeRequested.connect(
            lambda geom: popup.setGeometry(geom)
        )

        popup.show()
        popup.raise_()
        popup.activateWindow()
        return popup_page

    def acceptNavigationRequest(self, url: QUrl, nav_type, is_main_frame: bool) -> bool:
        return True

class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.config       = load_config()
        self.current_lang = self.config.get("lang", "pt-br")
        self.start_url    = self.config.get("last_url", URL)
        self._zoom        = float(self.config.get("zoom", 1.0))

        self.setWindowTitle(APP_NAME)
        self.resize(1400, 900)

        icon_path = USER_HOME / f".local/share/icons/hicolor/256x256/apps/{APP_ID}.png"
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        self._setup_profile()
        self._setup_browser()
        self._setup_toolbar()
        self._setup_progress_bar()
        self._setup_shortcuts()

    def _setup_profile(self) -> None:
        self.profile = QWebEngineProfile(APP_ID, self)
        storage = CONFIG_DIR / "storage"
        cache   = CONFIG_DIR / "cache"
        storage.mkdir(parents=True, exist_ok=True)
        cache.mkdir(parents=True, exist_ok=True)
        self.profile.setPersistentStoragePath(str(storage))
        self.profile.setCachePath(str(cache))
        self.profile.setPersistentCookiesPolicy(
            QWebEngineProfile.PersistentCookiesPolicy.AllowPersistentCookies
        )
        self.profile.setHttpUserAgent(
            "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
        )
        # Limita cache HTTP a 50 MB (padrão é ilimitado)
        self.profile.setHttpCacheMaximumSize(50 * 1024 * 1024)
        self.profile.downloadRequested.connect(self._handle_download)

    def _setup_browser(self) -> None:
        self.browser = QWebEngineView()
        self.browser.setPage(ClawPage(self.profile, self.browser))

        settings = self.browser.settings()
        settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptCanAccessClipboard, True)
        if hasattr(QWebEngineSettings.WebAttribute, "JavascriptCanPasteFromClipboard"):
            settings.setAttribute(QWebEngineSettings.WebAttribute.JavascriptCanPasteFromClipboard, True)
        # Desabilita features que consomem memória e não são necessárias
        settings.setAttribute(QWebEngineSettings.WebAttribute.PluginsEnabled, False)
        settings.setAttribute(QWebEngineSettings.WebAttribute.PdfViewerEnabled, False)
        settings.setAttribute(QWebEngineSettings.WebAttribute.PrintElementBackgrounds, False)

        self.browser.setUrl(QUrl(self.start_url))
        self.browser.setZoomFactor(self._zoom)
        self.browser.urlChanged.connect(self._update_url_bar)
        self.browser.loadStarted.connect(self._on_load_started)
        self.browser.loadFinished.connect(self._on_load_finished)
        self.setCentralWidget(self.browser)

    def _setup_toolbar(self) -> None:
        self.toolbar = QToolBar()
        self.toolbar.setMovable(False)
        self.addToolBar(self.toolbar)
        self._build_toolbar()

    def _build_toolbar(self) -> None:
        t = TRANSLATIONS[self.current_lang]
        tb = self.toolbar
        tb.clear()

        self._act_back    = QAction(t["back"], self)
        self._act_forward = QAction(t["forward"], self)
        self._act_refresh = QAction(t["refresh"], self)
        self._act_home    = QAction(t["home"], self)
        self._act_zoomin  = QAction(t["zoom_in"], self)
        self._act_zoomout = QAction(t["zoom_out"], self)

        self._act_back.setShortcut(QKeySequence.StandardKey.Back)
        self._act_forward.setShortcut(QKeySequence.StandardKey.Forward)
        self._act_refresh.setShortcut(QKeySequence.StandardKey.Refresh)

        self._act_back.triggered.connect(self.browser.back)
        self._act_forward.triggered.connect(self.browser.forward)
        self._act_refresh.triggered.connect(self.browser.reload)
        self._act_home.triggered.connect(lambda: self.browser.setUrl(QUrl(URL)))
        self._act_zoomin.triggered.connect(self._zoom_in)
        self._act_zoomout.triggered.connect(self._zoom_out)

        for act in (self._act_back, self._act_forward, self._act_refresh, self._act_home):
            tb.addAction(act)

        tb.addSeparator()

        self.url_bar = QLineEdit()
        self.url_bar.setPlaceholderText(t["url_placeholder"])
        self.url_bar.returnPressed.connect(self._navigate_to_url)
        self.url_bar.setText(self.browser.url().toString())
        self.url_bar.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Preferred)
        tb.addWidget(self.url_bar)

        tb.addSeparator()
        tb.addAction(self._act_zoomin)
        tb.addAction(self._act_zoomout)
        tb.addSeparator()

        self._lang_label = QLabel(t["lang_label"])
        tb.addWidget(self._lang_label)

        self._lang_combo = QComboBox()
        self._lang_combo.addItem("Português", "pt-br")
        self._lang_combo.addItem("English", "en")
        idx = self._lang_combo.findData(self.current_lang)
        if idx >= 0:
            self._lang_combo.setCurrentIndex(idx)
        self._lang_combo.currentIndexChanged.connect(self._change_language)
        tb.addWidget(self._lang_combo)

    def _update_toolbar_texts(self) -> None:
        t = TRANSLATIONS[self.current_lang]
        self._act_back.setText(t["back"])
        self._act_forward.setText(t["forward"])
        self._act_refresh.setText(t["refresh"])
        self._act_home.setText(t["home"])
        self._act_zoomin.setText(t["zoom_in"])
        self._act_zoomout.setText(t["zoom_out"])
        self._lang_label.setText(t["lang_label"])
        self.url_bar.setPlaceholderText(t["url_placeholder"])

    def _setup_progress_bar(self) -> None:
        self.progress = QProgressBar()
        self.progress.setMaximumHeight(3)
        self.progress.setTextVisible(False)
        self.progress.setRange(0, 100)
        self.progress.hide()
        self.statusBar().addPermanentWidget(self.progress, 1)
        self.browser.loadProgress.connect(self._on_load_progress)

    def _setup_shortcuts(self) -> None:
        from PyQt6.QtGui import QShortcut
        QShortcut(QKeySequence("Ctrl++"),    self, self._zoom_in)
        QShortcut(QKeySequence("Ctrl+-"),    self, self._zoom_out)
        QShortcut(QKeySequence("Ctrl+0"),    self, self._zoom_reset)
        QShortcut(QKeySequence("F11"),       self, self._toggle_fullscreen)
        QShortcut(QKeySequence("F5"),        self, self.browser.reload)
        QShortcut(QKeySequence("Ctrl+R"),    self, self.browser.reload)
        QShortcut(QKeySequence("Alt+Home"),  self, lambda: self.browser.setUrl(QUrl(URL)))

    def _navigate_to_url(self) -> None:
        url = self.url_bar.text().strip()
        if not url:
            return
        if not url.startswith(("http://", "https://")):
            url = f"https://{url}"
        self.browser.setUrl(QUrl(url))

    def _update_url_bar(self, url: QUrl) -> None:
        self.url_bar.setText(url.toString())

    def _on_load_started(self) -> None:
        self.progress.show()
        self.progress.setValue(0)
        self.statusBar().showMessage(TRANSLATIONS[self.current_lang]["loading"])

    def _on_load_progress(self, value: int) -> None:
        self.progress.setValue(value)

    def _on_load_finished(self, ok: bool) -> None:
        self.progress.hide()
        if ok:
            self.config["last_url"] = self.browser.url().toString()
            save_config(self.config)
            self.statusBar().showMessage(TRANSLATIONS[self.current_lang]["ready"], 3000)

    def _change_language(self) -> None:
        new_lang = self._lang_combo.currentData()
        if new_lang and new_lang != self.current_lang:
            self.current_lang = new_lang
            self.config["lang"] = new_lang
            save_config(self.config)
            self._update_toolbar_texts()

    def _zoom_in(self) -> None:
        self._zoom = min(self._zoom + 0.1, 3.0)
        self._apply_zoom()

    def _zoom_out(self) -> None:
        self._zoom = max(self._zoom - 0.1, 0.3)
        self._apply_zoom()

    def _zoom_reset(self) -> None:
        self._zoom = 1.0
        self._apply_zoom()

    def _apply_zoom(self) -> None:
        self.browser.setZoomFactor(self._zoom)
        self.config["zoom"] = round(self._zoom, 1)
        save_config(self.config)

    def _toggle_fullscreen(self) -> None:
        if self.isFullScreen():
            self.showNormal()
        else:
            self.showFullScreen()

    def _handle_download(self, download: QWebEngineDownloadRequest) -> None:
        downloads_dir = USER_HOME / "Downloads"
        downloads_dir.mkdir(exist_ok=True)
        dest = downloads_dir / download.suggestedFileName()
        download.setDownloadDirectory(str(downloads_dir))
        download.setDownloadFileName(dest.name)
        download.accept()
        self.statusBar().showMessage(
            f"{TRANSLATIONS[self.current_lang]['download_saved']}: {dest.name}", 5000
        )

    def closeEvent(self, event) -> None:
        self.config["last_url"] = self.browser.url().toString()
        self.config["zoom"]     = round(self._zoom, 1)
        save_config(self.config)
        super().closeEvent(event)

def main() -> None:
    app = QApplication(sys.argv)
    app.setApplicationName(APP_ID)
    app.setApplicationDisplayName(APP_NAME)
    app.setDesktopFileName(APP_ID)

    window = MainWindow()
    t = TRANSLATIONS[window.current_lang]
    print(f"\033[1;32m[OK]\033[0m {t['starting']} {APP_NAME}...")
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
