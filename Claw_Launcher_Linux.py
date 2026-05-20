#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Nome do Script  : OneNote
Descrição       : Abre dashboard OneNote via PyQt6 WebEngine (Nativo KDE)
Autor           : Rafael Batista
Versão          : 1.0.2 (I18n Support)
"""

import sys
import os
import json
from pathlib import Path

# Configuração de Caminhos
USER_HOME = Path.home()
APP_ID   = "OneNote"
APP_NAME = "OneNote"
URL      = "https://onenote.cloud.microsoft/pt-br/"
CONFIG_DIR = USER_HOME / f".local/share/{APP_ID}"
CONFIG_FILE = CONFIG_DIR / "config.json"

# 1. Importações com correção para PyQt6 recente
try:
    from PyQt6.QtWidgets import QApplication, QMainWindow, QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QToolBar, QLabel, QComboBox, QLineEdit
    from PyQt6.QtGui import QKeySequence, QDesktopServices, QIcon, QAction
    from PyQt6.QtWebEngineWidgets import QWebEngineView
    from PyQt6.QtWebEngineCore import QWebEngineProfile, QWebEnginePage
    from PyQt6.QtCore import QUrl, QSize, Qt
except ImportError as e:
    print(f"\n\033[1;31m[ERRO DE DEPENDÊNCIA]\033[0m: {e}")
    sys.exit(1)

# ─────────────────────────────────────────────────────────────────────────────
# TRADUÇÕES E CONFIGURAÇÃO
# ─────────────────────────────────────────────────────────────────────────────

TRANSLATIONS = {
    "pt-br": {
        "back": "⬅️ Voltar",
        "forward": "➡️ Avançar",
        "refresh": "🔄 Recarregar",
        "lang_label": "Idioma:",
        "starting": "Iniciando"
    },
    "en": {
        "back": "⬅️ Back",
        "forward": "➡️ Forward",
        "refresh": "🔄 Refresh",
        "lang_label": "Language:",
        "starting": "Starting"
    }
}

def load_config():
    if not CONFIG_FILE.exists():
        return {"lang": "pt-br"}
    try:
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    except:
        return {"lang": "pt-br"}

def save_config(config):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f)

class CustomWebEnginePage(QWebEnginePage):
    def createWindow(self, web_window_type):
        new_view = QWebEngineView()
        new_page = CustomWebEnginePage(self.profile(), new_view)
        new_view.setPage(new_page)
        new_view.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)
        new_view.resize(900, 700)
        new_view.show()
        new_page.urlChanged.connect(lambda url, view=new_view: self.handle_popup_url(url, view))
        return new_page

    def acceptNavigationRequest(self, url, nav_type, is_main_frame):
        if url.isValid() and nav_type == QWebEnginePage.NavigationType.NavigationTypeLinkClicked:
            if self.should_open_default_browser(url):
                QDesktopServices.openUrl(url)
                return False
        return super().acceptNavigationRequest(url, nav_type, is_main_frame)

    def handle_popup_url(self, url, view):
        if not url.isValid():
            return
        if self.should_open_default_browser(url):
            QDesktopServices.openUrl(url)
            view.close()

    def should_open_default_browser(self, url):
        host = url.host().lower()
        if host.endswith("vscode.dev"):
            return False
        for allowed in ["login.microsoftonline.com", "microsoftonline.com", "microsoft.com", "github.com", "githubusercontent.com", "visualstudio.com", "visualstudio.microsoft.com"]:
            if host.endswith(allowed):
                return False
        return True

# ─────────────────────────────────────────────────────────────────────────────
# JANELA PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.config = load_config()
        self.current_lang = self.config.get("lang", "pt-br")
        self.start_url = self.config.get("last_url", URL)
        
        self.setWindowTitle(APP_NAME)
        self.resize(1400, 900)

        # Ícone
        icon_path = USER_HOME / f".local/share/icons/hicolor/256x256/apps/{APP_ID}.png"
        if icon_path.exists():
            self.setWindowIcon(QIcon(str(icon_path)))

        # Configuração de Profile (Cookies/Cache)
        profile = QWebEngineProfile.defaultProfile()
        storage_dir = USER_HOME / f".local/share/{APP_ID}/webengine"
        cache_dir = USER_HOME / f".local/share/{APP_ID}/cache"
        storage_dir.mkdir(parents=True, exist_ok=True)
        cache_dir.mkdir(parents=True, exist_ok=True)
        profile.setPersistentStoragePath(str(storage_dir))
        profile.setCachePath(str(cache_dir))

        # Navegador
        self.browser = QWebEngineView()
        self.browser.setPage(CustomWebEnginePage(profile, self.browser))
        self.browser.setUrl(QUrl(self.start_url))
        self.browser.urlChanged.connect(self.update_url_bar)
        self.browser.loadFinished.connect(self.on_load_finished)
        self.setCentralWidget(self.browser)

        # Barra de Ferramentas
        self.toolbar = QToolBar()
        self.addToolBar(self.toolbar)
        self.setup_toolbar()

    def setup_toolbar(self):
        self.toolbar.clear()
        texts = TRANSLATIONS[self.current_lang]

        # Botão Voltar
        self.back_action = QAction(texts["back"], self)
        self.back_action.setShortcut(QKeySequence.StandardKey.Back)
        self.back_action.triggered.connect(self.browser.back)
        self.toolbar.addAction(self.back_action)

        # Botão Avançar
        self.forward_action = QAction(texts["forward"], self)
        self.forward_action.setShortcut(QKeySequence.StandardKey.Forward)
        self.forward_action.triggered.connect(self.browser.forward)
        self.toolbar.addAction(self.forward_action)

        # Botão Recarregar
        self.refresh_action = QAction(texts["refresh"], self)
        self.refresh_action.setShortcut(QKeySequence.StandardKey.Refresh)
        self.refresh_action.triggered.connect(self.browser.reload)
        self.toolbar.addAction(self.refresh_action)

        self.toolbar.addSeparator()

        # Barra de navegação
        self.url_bar = QLineEdit()
        self.url_bar.setPlaceholderText("Digite uma URL e pressione Enter")
        self.url_bar.returnPressed.connect(self.navigate_to_url)
        self.url_bar.setText(self.browser.url().toString())
        self.toolbar.addWidget(self.url_bar)

        self.toolbar.addSeparator()

        # Seletor de Idioma
        lang_container = QHBoxLayout()
        self.lang_label = QLabel(texts["lang_label"])
        self.toolbar.addWidget(self.lang_label)
        
        self.lang_combo = QComboBox()
        self.lang_combo.addItem("Português", "pt-br")
        self.lang_combo.addItem("English", "en")
        
        # Define o index atual com base na config
        index = self.lang_combo.findData(self.current_lang)
        if index >= 0:
            self.lang_combo.setCurrentIndex(index)
            
        self.lang_combo.currentIndexChanged.connect(self.change_language)
        self.toolbar.addWidget(self.lang_combo)

    def change_language(self):
        new_lang = self.lang_combo.currentData()
        if new_lang != self.current_lang:
            self.current_lang = new_lang
            self.config["lang"] = new_lang
            save_config(self.config)
            self.setup_toolbar()

    def navigate_to_url(self):
        url = self.url_bar.text().strip()
        if not url:
            return
        if not QUrl(url).scheme():
            url = f"https://{url}"
        self.browser.setUrl(QUrl(url))

    def update_url_bar(self, url):
        self.url_bar.setText(url.toString())

    def on_load_finished(self, ok):
        if ok:
            self.config["last_url"] = self.browser.url().toString()
            save_config(self.config)

    def closeEvent(self, event):
        self.config["last_url"] = self.browser.url().toString()
        save_config(self.config)
        super().closeEvent(event)

def main():
    app = QApplication(sys.argv)
    app.setApplicationName(APP_ID)
    app.setApplicationDisplayName(APP_NAME)
    app.setDesktopFileName(APP_ID)

    window = MainWindow()
    
    lang_info = TRANSLATIONS[window.current_lang]["starting"]
    print(f"\033[1;32m[OK]\033[0m {lang_info} {APP_NAME}...")

    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
