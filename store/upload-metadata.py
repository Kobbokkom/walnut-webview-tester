#!/usr/bin/env python3
"""
App Store Connect API - Metadata Upload Script
Uploads app metadata for all supported languages
"""

import jwt
import time
import requests
import json
from pathlib import Path

# API Credentials
ISSUER_ID = "a7524762-b1db-463b-84a8-bbee51a37cc2"
KEY_ID = "74HC92L9NA"
PRIVATE_KEY_PATH = Path.home() / "Documents/API/AuthKey_74HC92L9NA.p8"

# App Store Connect API Base URL
BASE_URL = "https://api.appstoreconnect.apple.com/v1"

# Create session with timeout
session = requests.Session()
session.request = lambda method, url, **kwargs: requests.Session.request(session, method, url, timeout=kwargs.pop('timeout', 30), **kwargs)

# All supported locales (40 languages)
LOCALES = [
    "ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US",
    "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id",
    "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro",
    "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"
]

# Metadata translations
# Format: name (30 chars max), subtitle (30 chars max), description (4000 chars max), keywords (100 chars max)
METADATA = {
    "en-US": {
        "name": "Walnut: Webview Tester & Debug",
        "subtitle": "Agentic WebView Debugging",
        "description": """The ultimate developer tool for testing WKWebView and SFSafariViewController configurations in real-time.

MAC AGENT (NEW)
• Let a coding agent or your Mac terminal drive Walnut's WKWebView on your iPhone
• Open pages, tap and type, run scripts, and read Console and Network logs
• Choose approvals: ask every time, allow page actions, or allow everything
• Pair once over Wi-Fi or USB with a 6-digit confirmation

KEY FEATURES

WKWebView Testing
• Real-time configuration testing with 20+ options
• Built-in DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injection and snippet execution
• Custom User-Agent emulation
• Viewport and device emulation

SFSafariViewController Testing
• Native Safari experience with content blockers
• Reader mode and responsive size control
• Customizable bar colors and dismiss button styles

Developer Tools
• Console: Capture console.log with %c CSS styling support
• Network: Monitor fetch/XHR requests with timing data
• Storage: View/edit localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) and Navigation Timing
• Sources: DOM tree inspection, stylesheets, scripts
• Accessibility: axe-core based accessibility auditing

Additional Features
• Bookmark management for quick URL access
• Responsive viewport resizing (iPhone, iPad, Desktop presets)
• Screenshot capture
• API capability detection
• Dark mode support

Perfect for iOS developers who need to test web content rendering, debug JavaScript, analyze network requests, and ensure accessibility compliance.
""",
        "keywords": "webview,developer,debug,console,network,safari,wkwebview,devtools,test,inspect,ios,javascript,html",
        "promotionalText": "New: Mac Agent lets your coding agent test pages in Walnut from your Mac. Plus Console, Network and Sources built in for WebView debugging."
    },
    "en-AU": {
        "name": "Walnut: Webview Tester & Debug",
        "subtitle": "Agentic WebView Debugging",
        "description": """The ultimate developer tool for testing WKWebView and SFSafariViewController configurations in real-time.

MAC AGENT (NEW)
• Let a coding agent or your Mac terminal drive Walnut's WKWebView on your iPhone
• Open pages, tap and type, run scripts, and read Console and Network logs
• Choose approvals: ask every time, allow page actions, or allow everything
• Pair once over Wi-Fi or USB with a 6-digit confirmation

KEY FEATURES

WKWebView Testing
• Real-time configuration testing with 20+ options
• Built-in DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injection and snippet execution
• Custom User-Agent emulation
• Viewport and device emulation

SFSafariViewController Testing
• Native Safari experience with content blockers
• Reader mode and responsive size control
• Customizable bar colors and dismiss button styles

Developer Tools
• Console: Capture console.log with %c CSS styling support
• Network: Monitor fetch/XHR requests with timing data
• Storage: View/edit localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) and Navigation Timing
• Sources: DOM tree inspection, stylesheets, scripts
• Accessibility: axe-core based accessibility auditing

Additional Features
• Bookmark management for quick URL access
• Responsive viewport resizing (iPhone, iPad, Desktop presets)
• Screenshot capture
• API capability detection
• Dark mode support

Perfect for iOS developers who need to test web content rendering, debug JavaScript, analyze network requests, and ensure accessibility compliance.
""",
        "keywords": "webview,developer,debug,console,network,safari,wkwebview,devtools,test,inspect,ios,javascript,html",
        "promotionalText": "New: Mac Agent lets your coding agent test pages in Walnut from your Mac. Plus Console, Network and Sources built in for WebView debugging."
    },
    "en-CA": {
        "name": "Walnut: Webview Tester & Debug",
        "subtitle": "Agentic WebView Debugging",
        "description": """The ultimate developer tool for testing WKWebView and SFSafariViewController configurations in real-time.

MAC AGENT (NEW)
• Let a coding agent or your Mac terminal drive Walnut's WKWebView on your iPhone
• Open pages, tap and type, run scripts, and read Console and Network logs
• Choose approvals: ask every time, allow page actions, or allow everything
• Pair once over Wi-Fi or USB with a 6-digit confirmation

KEY FEATURES

WKWebView Testing
• Real-time configuration testing with 20+ options
• Built-in DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injection and snippet execution
• Custom User-Agent emulation
• Viewport and device emulation

SFSafariViewController Testing
• Native Safari experience with content blockers
• Reader mode and responsive size control
• Customizable bar colors and dismiss button styles

Developer Tools
• Console: Capture console.log with %c CSS styling support
• Network: Monitor fetch/XHR requests with timing data
• Storage: View/edit localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) and Navigation Timing
• Sources: DOM tree inspection, stylesheets, scripts
• Accessibility: axe-core based accessibility auditing

Additional Features
• Bookmark management for quick URL access
• Responsive viewport resizing (iPhone, iPad, Desktop presets)
• Screenshot capture
• API capability detection
• Dark mode support

Perfect for iOS developers who need to test web content rendering, debug JavaScript, analyze network requests, and ensure accessibility compliance.
""",
        "keywords": "webview,developer,debug,console,network,safari,wkwebview,devtools,test,inspect,ios,javascript,html",
        "promotionalText": "New: Mac Agent lets your coding agent test pages in Walnut from your Mac. Plus Console, Network and Sources built in for WebView debugging."
    },
    "en-GB": {
        "name": "Walnut: Webview Tester & Debug",
        "subtitle": "Agentic WebView Debugging",
        "description": """The ultimate developer tool for testing WKWebView and SFSafariViewController configurations in real-time.

MAC AGENT (NEW)
• Let a coding agent or your Mac terminal drive Walnut's WKWebView on your iPhone
• Open pages, tap and type, run scripts, and read Console and Network logs
• Choose approvals: ask every time, allow page actions, or allow everything
• Pair once over Wi-Fi or USB with a 6-digit confirmation

KEY FEATURES

WKWebView Testing
• Real-time configuration testing with 20+ options
• Built-in DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injection and snippet execution
• Custom User-Agent emulation
• Viewport and device emulation

SFSafariViewController Testing
• Native Safari experience with content blockers
• Reader mode and responsive size control
• Customizable bar colors and dismiss button styles

Developer Tools
• Console: Capture console.log with %c CSS styling support
• Network: Monitor fetch/XHR requests with timing data
• Storage: View/edit localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) and Navigation Timing
• Sources: DOM tree inspection, stylesheets, scripts
• Accessibility: axe-core based accessibility auditing

Additional Features
• Bookmark management for quick URL access
• Responsive viewport resizing (iPhone, iPad, Desktop presets)
• Screenshot capture
• API capability detection
• Dark mode support

Perfect for iOS developers who need to test web content rendering, debug JavaScript, analyze network requests, and ensure accessibility compliance.
""",
        "keywords": "webview,developer,debug,console,network,safari,wkwebview,devtools,test,inspect,ios,javascript,html",
        "promotionalText": "New: Mac Agent lets your coding agent test pages in Walnut from your Mac. Plus Console, Network and Sources built in for WebView debugging."
    },
    "ko": {
        "name": "Walnut: Webview 테스터 & 디버그",
        "subtitle": "에이전트로 WebView 디버깅",
        "description": """WKWebView와 SFSafariViewController 설정을 실시간으로 테스트하는 개발자 도구입니다.

MAC AGENT (신규)
• 코딩 에이전트나 Mac 터미널로 iPhone의 Walnut WKWebView를 제어하세요
• 페이지 열기, 탭과 입력, 스크립트 실행, Console 및 Network 로그 읽기
• 승인 방식을 선택하세요: 매번 묻기, 페이지 작업 허용, 모두 허용
• Wi-Fi 또는 USB로 한 번 페어링하고 6자리 코드로 확인

주요 기능

WKWebView 테스트
• 20개 이상의 옵션으로 실시간 설정 테스트
• 내장 DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript 주입 및 스니펫 실행
• 커스텀 User-Agent 에뮬레이션
• 뷰포트 및 디바이스 에뮬레이션

SFSafariViewController 테스트
• 콘텐츠 차단기를 포함한 네이티브 Safari 경험
• Reader Mode 및 반응형 크기 조절
• 바 색상 및 닫기 버튼 스타일 커스터마이징

개발자 도구
• Console: %c CSS 스타일링을 지원하는 console.log 캡처
• Network: 타이밍 데이터와 함께 fetch/XHR 요청 모니터링
• Storage: localStorage, sessionStorage, 쿠키 조회/편집
• Performance: Web Vitals (LCP, FID, CLS) 및 Navigation Timing
• Sources: DOM 트리 검사, 스타일시트, 스크립트
• Accessibility: axe-core 기반 접근성 감사

추가 기능
• 빠른 URL 접근을 위한 북마크 관리
• 반응형 뷰포트 크기 조절 (iPhone, iPad, Desktop 프리셋)
• 스크린샷 캡처
• API 기능 감지
• 다크 모드 지원

웹 콘텐츠 렌더링 테스트, JavaScript 디버깅, 네트워크 요청 분석, 접근성 준수 확인이 필요한 iOS 개발자에게 적합합니다.
""",
        "keywords": "웹뷰,개발자,디버그,콘솔,네트워크,사파리,devtools,테스트,검사,ios,자바스크립트,html,css,쿠키,성능,접근성,개발도구,브라우저,앱,모바일,웹킷,사파리뷰",
        "promotionalText": "새로운 Mac Agent로 Mac의 코딩 에이전트가 Walnut에서 페이지를 테스트합니다. WebView 디버깅용 Console, Network, Sources도 내장."
    },
    "ja": {
        "name": "Walnut: Webview テスター＆デバッグ",
        "subtitle": "エージェントでWebViewデバッグ",
        "description": """WKWebViewとSFSafariViewControllerの設定をリアルタイムでテストする開発者ツールです。

MAC AGENT (新機能)
• コーディングエージェントやMacのターミナルから、iPhone上のWalnutのWKWebViewを操作
• ページを開く、タップや入力、スクリプト実行、ConsoleとNetworkログの確認
• 承認を選択: 毎回確認、ページ操作を許可、すべて許可
• Wi-FiまたはUSBで一度ペアリングし、6桁コードで確認

主な機能

WKWebViewテスト
• 20以上のオプションでリアルタイム設定テスト
• 内蔵DevTools：Console、Network、Storage、Performance、Sources、Accessibility
• JavaScript注入とスニペット実行
• カスタムUser-Agentエミュレーション
• ビューポートとデバイスエミュレーション

SFSafariViewControllerテスト
• コンテンツブロッカーを含むネイティブSafari体験
• Reader Modeとレスポンシブサイズ調整
• バーの色と閉じるボタンスタイルのカスタマイズ

開発者ツール
• Console：%c CSSスタイリングをサポートするconsole.logキャプチャ
• Network：タイミングデータ付きfetch/XHRリクエスト監視
• Storage：localStorage、sessionStorage、クッキーの表示/編集
• Performance：Web Vitals（LCP、FID、CLS）とNavigation Timing
• Sources：DOMツリー検査、スタイルシート、スクリプト
• Accessibility：axe-coreベースのアクセシビリティ監査

追加機能
• クイックURLアクセス用ブックマーク管理
• レスポンシブビューポートサイズ変更（iPhone、iPad、Desktopプリセット）
• スクリーンショットキャプチャ
• API機能検出
• ダークモードサポート

Webコンテンツのレンダリングテスト、JavaScriptデバッグ、ネットワークリクエスト分析、アクセシビリティ準拠の確認が必要なiOS開発者に最適です。
""",
        "keywords": "webview,開発者,デバッグ,コンソール,ネットワーク,safari,devtools,テスト,検査,ios,javascript,html,css,開発ツール,ブラウザ,アプリ",
        "promotionalText": "新機能: Mac Agentで、MacからコーディングエージェントがWalnut内のページをテスト。WebViewデバッグ用のConsole、Network、Sourcesも内蔵。"
    },
    "zh-Hans": {
        "name": "Walnut: Webview 测试与调试",
        "subtitle": "智能体 WebView 调试",
        "description": """实时测试WKWebView和SFSafariViewController配置的开发者工具。

MAC AGENT (新)
• 让编码代理或你的 Mac 终端在 iPhone 上操控 Walnut 的 WKWebView
• 打开页面、点击和输入、运行脚本，并读取 Console 和 Network 日志
• 选择授权方式：每次询问、允许页面操作，或允许所有操作
• 通过 Wi-Fi 或 USB 完成一次配对，并使用 6 位数字确认码

主要功能

WKWebView测试
• 20多个选项的实时配置测试
• 内置DevTools：Console、Network、Storage、Performance、Sources、Accessibility
• JavaScript注入和代码片段执行
• 自定义User-Agent模拟
• 视口和设备模拟

SFSafariViewController测试
• 支持内容拦截器的原生Safari体验
• Reader Mode和响应式尺寸控制
• 可自定义栏颜色和关闭按钮样式

开发者工具
• Console：支持%c CSS样式的console.log捕获
• Network：带时间数据的fetch/XHR请求监控
• Storage：查看/编辑localStorage、sessionStorage、cookies
• Performance：Web Vitals（LCP、FID、CLS）和Navigation Timing
• Sources：DOM树检查、样式表、脚本
• Accessibility：基于axe-core的可访问性审计

其他功能
• 快速URL访问的书签管理
• 响应式视口大小调整（iPhone、iPad、Desktop预设）
• 截图捕获
• API功能检测
• 深色模式支持

非常适合需要测试网页内容渲染、调试JavaScript、分析网络请求和确保可访问性合规的iOS开发者。
""",
        "keywords": "webview,开发者,调试,控制台,网络,safari,devtools,测试,检查,ios,javascript,html,css,cookie,性能,开发工具,浏览器,应用,工具",
        "promotionalText": "全新 Mac Agent 可让你的编码代理从 Mac 在 Walnut 中测试页面。内置 Console、Network 和 Sources，方便调试 WebView。"
    },
    "zh-Hant": {
        "name": "Walnut: Webview 測試與除錯",
        "subtitle": "智慧代理 WebView 除錯",
        "description": """即時測試WKWebView和SFSafariViewController配置的開發者工具。

MAC AGENT (新)
• 讓編碼代理或你的 Mac 終端機操控 iPhone 上 Walnut 的 WKWebView
• 開啟頁面、點一下並輸入、執行腳本，以及讀取 Console 和 Network 記錄
• 選擇核准方式：每次詢問、允許頁面操作，或允許所有操作
• 透過 Wi-Fi 或 USB 配對一次，並以 6 位數確認

主要功能

WKWebView測試
• 20多個選項的即時配置測試
• 內建DevTools：Console、Network、Storage、Performance、Sources、Accessibility
• JavaScript注入和程式碼片段執行
• 自訂User-Agent模擬
• 視口和裝置模擬

SFSafariViewController測試
• 支援內容阻擋器的原生Safari體驗
• Reader Mode和響應式尺寸控制
• 可自訂列顏色和關閉按鈕樣式

開發者工具
• Console：支援%c CSS樣式的console.log擷取
• Network：帶時間資料的fetch/XHR請求監控
• Storage：檢視/編輯localStorage、sessionStorage、cookies
• Performance：Web Vitals（LCP、FID、CLS）和Navigation Timing
• Sources：DOM樹檢查、樣式表、指令碼
• Accessibility：基於axe-core的無障礙稽核

其他功能
• 快速URL存取的書籤管理
• 響應式視口大小調整（iPhone、iPad、Desktop預設）
• 螢幕截圖擷取
• API功能偵測
• 深色模式支援

非常適合需要測試網頁內容呈現、除錯JavaScript、分析網路請求和確保無障礙合規的iOS開發者。
""",
        "keywords": "webview,開發者,除錯,控制台,網路,safari,devtools,測試,檢查,ios,javascript,html,css,cookie,效能,開發工具,瀏覽器,應用,工具",
        "promotionalText": "全新：Mac Agent 可讓你的編碼代理從 Mac 測試 Walnut 中的頁面。內建 Console、Network 和 Sources，方便 WebView 除錯。"
    },
    "de-DE": {
        "name": "Walnut: Webview Tester & Debug",
        "subtitle": "Agentisches WebView-Debugging",
        "description": """Das ultimative Entwicklertool zum Testen von WKWebView- und SFSafariViewController-Konfigurationen in Echtzeit.

MAC AGENT (NEU)
• Lass einen Coding-Agenten oder dein Mac-Terminal die WKWebView von Walnut auf deinem iPhone steuern
• Öffne Seiten, tippe und gib Text ein, führe Skripte aus und lies Console- und Network-Logs
• Wähle Freigaben: jedes Mal nachfragen, Seitenaktionen erlauben oder alles erlauben
• Kopple einmal über Wi-Fi oder USB mit 6-stelliger Bestätigung

HAUPTFUNKTIONEN

WKWebView-Tests
• Echtzeit-Konfigurationstests mit über 20 Optionen
• Integrierte DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-Injection und Snippet-Ausführung
• Benutzerdefinierte User-Agent-Emulation
• Viewport- und Geräte-Emulation

SFSafariViewController-Tests
• Native Safari-Erfahrung mit Content Blockern
• Reader Mode und responsive Größenanpassung
• Anpassbare Leistenfarben und Schließen-Schaltflächen

Entwicklertools
• Console: console.log-Erfassung mit %c CSS-Styling-Unterstützung
• Network: Fetch/XHR-Anfragen mit Timing-Daten überwachen
• Storage: localStorage, sessionStorage, Cookies anzeigen/bearbeiten
• Performance: Web Vitals (LCP, FID, CLS) und Navigation Timing
• Sources: DOM-Baum-Inspektion, Stylesheets, Skripte
• Accessibility: axe-core-basierte Barrierefreiheitsprüfung

Zusätzliche Funktionen
• Lesezeichenverwaltung für schnellen URL-Zugriff
• Responsive Viewport-Größenanpassung (iPhone, iPad, Desktop-Presets)
• Screenshot-Erfassung
• API-Fähigkeitserkennung
• Dunkelmodus-Unterstützung

Perfekt für iOS-Entwickler, die Web-Content-Rendering testen, JavaScript debuggen, Netzwerkanfragen analysieren und Barrierefreiheit sicherstellen müssen.
""",
        "keywords": "webview,entwickler,debug,konsole,netzwerk,safari,devtools,test,inspektor,ios,javascript,html,browser",
        "promotionalText": "Neu: Mit Mac Agent testet dein Coding-Agent Seiten in Walnut von deinem Mac aus. Plus Console, Network und Sources für WebView-Debugging."
    },
    "fr-FR": {
        "name": "Walnut: Webview Test & Débogage",
        "subtitle": "Débogage WebView par agent",
        "description": """L'outil ultime pour les développeurs pour tester les configurations WKWebView et SFSafariViewController en temps réel.

MAC AGENT (NOUVEAU)
• Permettez à un agent de codage ou au terminal de votre Mac de piloter le WKWebView de Walnut sur votre iPhone
• Ouvrez des pages, touchez et saisissez du texte, exécutez des scripts, et consultez les logs Console et Network
• Choisissez les approbations : demander à chaque fois, autoriser les actions de page, ou tout autoriser
• Jumelez une fois via Wi-Fi ou USB avec une confirmation à 6 chiffres

FONCTIONNALITÉS PRINCIPALES

Tests WKWebView
• Tests de configuration en temps réel avec plus de 20 options
• DevTools intégrés : Console, Network, Storage, Performance, Sources, Accessibility
• Injection JavaScript et exécution de snippets
• Émulation User-Agent personnalisée
• Émulation de viewport et d'appareil

Tests SFSafariViewController
• Expérience Safari native avec bloqueurs de contenu
• Reader Mode et contrôle de taille réactif
• Couleurs de barre et styles de bouton personnalisables

Outils de développement
• Console : Capture console.log avec support du style CSS %c
• Network : Surveillance des requêtes fetch/XHR avec données de timing
• Storage : Afficher/modifier localStorage, sessionStorage, cookies
• Performance : Web Vitals (LCP, FID, CLS) et Navigation Timing
• Sources : Inspection de l'arbre DOM, feuilles de style, scripts
• Accessibility : Audit d'accessibilité basé sur axe-core

Fonctionnalités supplémentaires
• Gestion des favoris pour un accès URL rapide
• Redimensionnement de viewport réactif (préréglages iPhone, iPad, Desktop)
• Capture d'écran
• Détection des capacités API
• Support du mode sombre

Parfait pour les développeurs iOS qui doivent tester le rendu de contenu web, déboguer JavaScript, analyser les requêtes réseau et assurer la conformité d'accessibilité.
""",
        "keywords": "webview,développeur,debug,console,réseau,safari,devtools,test,inspecteur,ios,javascript,html,cookie",
        "promotionalText": "Nouveau : Mac Agent permet à votre agent de codage de tester des pages dans Walnut depuis votre Mac. Avec Console, Network et Sources pour déboguer WebView."
    },
    "fr-CA": {
        "name": "Walnut: Webview Test & Débogage",
        "subtitle": "Débogage WebView par agent",
        "description": """L'outil ultime pour les développeurs pour tester les configurations WKWebView et SFSafariViewController en temps réel.

MAC AGENT (NOUVEAU)
• Permettez à un agent de codage ou au terminal de votre Mac de piloter le WKWebView de Walnut sur votre iPhone
• Ouvrez des pages, touchez et saisissez du texte, exécutez des scripts, et consultez les journaux Console et Network
• Choisissez les approbations : demander chaque fois, autoriser les actions sur la page ou tout autoriser
• Jumelez une fois via Wi-Fi ou USB avec une confirmation à 6 chiffres

FONCTIONNALITÉS PRINCIPALES

Tests WKWebView
• Tests de configuration en temps réel avec plus de 20 options
• DevTools intégrés : Console, Network, Storage, Performance, Sources, Accessibility
• Injection JavaScript et exécution de snippets
• Émulation User-Agent personnalisée
• Émulation de viewport et d'appareil

Tests SFSafariViewController
• Expérience Safari native avec bloqueurs de contenu
• Reader Mode et contrôle de taille réactif
• Couleurs de barre et styles de bouton personnalisables

Outils de développement
• Console : Capture console.log avec support du style CSS %c
• Network : Surveillance des requêtes fetch/XHR avec données de timing
• Storage : Afficher/modifier localStorage, sessionStorage, cookies
• Performance : Web Vitals (LCP, FID, CLS) et Navigation Timing
• Sources : Inspection de l'arbre DOM, feuilles de style, scripts
• Accessibility : Audit d'accessibilité basé sur axe-core

Fonctionnalités supplémentaires
• Gestion des favoris pour un accès URL rapide
• Redimensionnement de viewport réactif (préréglages iPhone, iPad, Desktop)
• Capture d'écran
• Détection des capacités API
• Support du mode sombre

Parfait pour les développeurs iOS qui doivent tester le rendu de contenu web, déboguer JavaScript, analyser les requêtes réseau et assurer la conformité d'accessibilité.
""",
        "keywords": "webview,développeur,debug,console,réseau,safari,devtools,test,inspecteur,ios,javascript,html,cookie",
        "promotionalText": "Nouveau : Mac Agent permet à votre agent de codage de tester des pages dans Walnut depuis votre Mac. Console, Network et Sources intégrés pour déboguer WebView."
    },
    "es-ES": {
        "name": "Walnut: Webview Test & Depuración",
        "subtitle": "Depuración WebView con agentes",
        "description": """La herramienta definitiva para desarrolladores para probar configuraciones de WKWebView y SFSafariViewController en tiempo real.

MAC AGENT (NUEVO)
• Permite que un agente de programación o el terminal de tu Mac controle WKWebView de Walnut en tu iPhone
• Abre páginas, toca y escribe, ejecuta scripts y lee registros de Console y Network
• Elige aprobaciones: preguntar siempre, permitir acciones en la página o permitir todo
• Enlaza una vez por Wi-Fi o USB con una confirmación de 6 dígitos

CARACTERÍSTICAS PRINCIPALES

Pruebas de WKWebView
• Pruebas de configuración en tiempo real con más de 20 opciones
• DevTools integradas: Console, Network, Storage, Performance, Sources, Accessibility
• Inyección de JavaScript y ejecución de snippets
• Emulación de User-Agent personalizado
• Emulación de viewport y dispositivo

Pruebas de SFSafariViewController
• Experiencia Safari nativa con bloqueadores de contenido
• Reader Mode y control de tamaño responsivo
• Colores de barra y estilos de botón personalizables

Herramientas de desarrollo
• Console: Captura de console.log con soporte de estilo CSS %c
• Network: Monitoreo de solicitudes fetch/XHR con datos de tiempo
• Storage: Ver/editar localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) y Navigation Timing
• Sources: Inspección del árbol DOM, hojas de estilo, scripts
• Accessibility: Auditoría de accesibilidad basada en axe-core

Características adicionales
• Gestión de marcadores para acceso rápido a URLs
• Redimensionamiento de viewport responsivo (presets iPhone, iPad, Desktop)
• Captura de pantalla
• Detección de capacidades de API
• Soporte de modo oscuro

Perfecto para desarrolladores iOS que necesitan probar el renderizado de contenido web, depurar JavaScript, analizar solicitudes de red y asegurar el cumplimiento de accesibilidad.
""",
        "keywords": "webview,desarrollador,debug,consola,red,safari,devtools,prueba,inspector,ios,javascript,html,cookie",
        "promotionalText": "Nuevo: Mac Agent permite a tu agente probar páginas en Walnut desde tu Mac. Además, Console, Network y Sources integrados para depurar WebView."
    },
    "es-MX": {
        "name": "Walnut: Webview Test & Depuración",
        "subtitle": "Depuración WebView con agentes",
        "description": """La herramienta definitiva para desarrolladores para probar configuraciones de WKWebView y SFSafariViewController en tiempo real.

MAC AGENT (NUEVO)
• Permite que un agente de programación o la terminal de tu Mac controle el WKWebView de Walnut en tu iPhone
• Abre páginas, toca y escribe, ejecuta scripts y lee registros de Console y Network
• Elige aprobaciones: preguntar siempre, permitir acciones en la página o permitir todo
• Enlaza una vez por Wi-Fi o USB con una confirmación de 6 dígitos

CARACTERÍSTICAS PRINCIPALES

Pruebas de WKWebView
• Pruebas de configuración en tiempo real con más de 20 opciones
• DevTools integradas: Console, Network, Storage, Performance, Sources, Accessibility
• Inyección de JavaScript y ejecución de snippets
• Emulación de User-Agent personalizado
• Emulación de viewport y dispositivo

Pruebas de SFSafariViewController
• Experiencia Safari nativa con bloqueadores de contenido
• Reader Mode y control de tamaño responsivo
• Colores de barra y estilos de botón personalizables

Herramientas de desarrollo
• Console: Captura de console.log con soporte de estilo CSS %c
• Network: Monitoreo de solicitudes fetch/XHR con datos de tiempo
• Storage: Ver/editar localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) y Navigation Timing
• Sources: Inspección del árbol DOM, hojas de estilo, scripts
• Accessibility: Auditoría de accesibilidad basada en axe-core

Características adicionales
• Gestión de marcadores para acceso rápido a URLs
• Redimensionamiento de viewport responsivo (presets iPhone, iPad, Desktop)
• Captura de pantalla
• Detección de capacidades de API
• Soporte de modo oscuro

Perfecto para desarrolladores iOS que necesitan probar el renderizado de contenido web, depurar JavaScript, analizar solicitudes de red y asegurar el cumplimiento de accesibilidad.
""",
        "keywords": "webview,desarrollador,debug,consola,red,safari,devtools,prueba,inspector,ios,javascript,html,cookie",
        "promotionalText": "Nuevo: Mac Agent permite que tu agente de programación pruebe páginas en Walnut desde tu Mac. Con Console, Network y Sources para depurar WebView."
    },
    "it": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Debug WebView con agenti",
        "description": """Lo strumento definitivo per sviluppatori per testare le configurazioni di WKWebView e SFSafariViewController in tempo reale.

MAC AGENT (NUOVO)
• Consenti a un agente di coding o al terminale del tuo Mac di controllare WKWebView di Walnut sul tuo iPhone
• Apri pagine, tocca e digita, esegui script e leggi i log di Console e Network
• Scegli le approvazioni: chiedi ogni volta, consenti azioni sulla pagina o consenti tutto
• Abbina una volta tramite Wi-Fi o USB con conferma a 6 cifre

CARATTERISTICHE PRINCIPALI

Test WKWebView
• Test di configurazione in tempo reale con oltre 20 opzioni
• DevTools integrati: Console, Network, Storage, Performance, Sources, Accessibility
• Iniezione JavaScript ed esecuzione di snippet
• Emulazione User-Agent personalizzata
• Emulazione viewport e dispositivo

Test SFSafariViewController
• Esperienza Safari nativa con blocco contenuti
• Reader Mode e controllo dimensioni reattivo
• Colori della barra e stili dei pulsanti personalizzabili
• Compatibilità estensioni Safari

Strumenti per sviluppatori
• Console: Cattura console.log con supporto stile CSS %c
• Network: Monitoraggio richieste fetch/XHR con dati di timing
• Storage: Visualizza/modifica localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) e Navigation Timing
• Sources: Ispezione albero DOM, fogli di stile, script
• Accessibility: Audit accessibilità basato su axe-core

Funzionalità aggiuntive
• Gestione segnalibri per accesso URL rapido
• Ridimensionamento viewport responsivo (preset iPhone, iPad, Desktop)
• Cattura screenshot
• Rilevamento capacità API
• Supporto modalità scura

Perfetto per sviluppatori iOS che devono testare il rendering di contenuti web, debuggare JavaScript, analizzare richieste di rete e garantire la conformità all'accessibilità.
""",
        "keywords": "webview,sviluppatore,debug,console,rete,safari,devtools,test,ispettore,ios,javascript,html,css",
        "promotionalText": "Novità: Mac Agent permette al tuo agente di coding di testare pagine in Walnut dal tuo Mac. Console, Network e Sources integrati per il debug WebView."
    },
    "pt-BR": {
        "name": "Walnut: Webview Teste & Debug",
        "subtitle": "Depuração WebView com agentes",
        "description": """A ferramenta definitiva para desenvolvedores testarem configurações de WKWebView e SFSafariViewController em tempo real.

MAC AGENT (NOVO)
• Permita que um agente de código ou o terminal do Mac controle o WKWebView do Walnut no seu iPhone
• Abra páginas, toque e digite, execute scripts e leia logs do Console e Network
• Escolha aprovações: perguntar sempre, permitir ações na página ou permitir tudo
• Emparelhe uma vez por Wi-Fi ou USB com uma confirmação de 6 dígitos

RECURSOS PRINCIPAIS

Testes de WKWebView
• Testes de configuração em tempo real com mais de 20 opções
• DevTools integradas: Console, Network, Storage, Performance, Sources, Accessibility
• Injeção de JavaScript e execução de snippets
• Emulação de User-Agent personalizado
• Emulação de viewport e dispositivo

Testes de SFSafariViewController
• Experiência Safari nativa com bloqueadores de conteúdo
• Reader Mode e controle de tamanho responsivo
• Cores da barra e estilos de botão personalizáveis
• Compatibilidade com extensões do Safari

Ferramentas de desenvolvedor
• Console: Captura de console.log com suporte a estilo CSS %c
• Network: Monitoramento de requisições fetch/XHR com dados de tempo
• Storage: Visualizar/editar localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) e Navigation Timing
• Sources: Inspeção da árvore DOM, folhas de estilo, scripts
• Accessibility: Auditoria de acessibilidade baseada em axe-core

Recursos adicionais
• Gerenciamento de favoritos para acesso rápido a URLs
• Redimensionamento de viewport responsivo (presets iPhone, iPad, Desktop)
• Captura de tela
• Detecção de capacidades de API
• Suporte ao modo escuro

Perfeito para desenvolvedores iOS que precisam testar renderização de conteúdo web, depurar JavaScript, analisar requisições de rede e garantir conformidade de acessibilidade.
""",
        "keywords": "webview,desenvolvedor,debug,console,rede,safari,devtools,teste,inspetor,ios,javascript,html,cookie",
        "promotionalText": "Novo: Mac Agent permite que seu agente de código teste páginas no Walnut pelo Mac. Console, Network e Sources integrados para depurar WebView."
    },
    "pt-PT": {
        "name": "Walnut: Webview Teste & Debug",
        "subtitle": "Depuração WebView com agentes",
        "description": """A ferramenta definitiva para desenvolvedores testarem configurações de WKWebView e SFSafariViewController em tempo real.

MAC AGENT (NOVO)
• Permita que um agente de programação ou o terminal do Mac controle o WKWebView do Walnut no iPhone
• Abra páginas, toque e escreva, execute scripts e leia registos de Console e Network
• Escolha aprovações: perguntar sempre, permitir ações na página ou permitir tudo
• Emparelhe uma vez por Wi-Fi ou USB com uma confirmação de 6 dígitos

RECURSOS PRINCIPAIS

Testes de WKWebView
• Testes de configuração em tempo real com mais de 20 opções
• DevTools integradas: Console, Network, Storage, Performance, Sources, Accessibility
• Injeção de JavaScript e execução de snippets
• Emulação de User-Agent personalizado
• Emulação de viewport e dispositivo

Testes de SFSafariViewController
• Experiência Safari nativa com bloqueadores de conteúdo
• Reader Mode e controle de tamanho responsivo
• Cores da barra e estilos de botão personalizáveis
• Compatibilidade com extensões do Safari

Ferramentas de desenvolvedor
• Console: Captura de console.log com suporte a estilo CSS %c
• Network: Monitoramento de requisições fetch/XHR com dados de tempo
• Storage: Visualizar/editar localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) e Navigation Timing
• Sources: Inspeção da árvore DOM, folhas de estilo, scripts
• Accessibility: Auditoria de acessibilidade baseada em axe-core

Recursos adicionais
• Gerenciamento de favoritos para acesso rápido a URLs
• Redimensionamento de viewport responsivo (presets iPhone, iPad, Desktop)
• Captura de tela
• Detecção de capacidades de API
• Suporte ao modo escuro

Perfeito para desenvolvedores iOS que precisam testar renderização de conteúdo web, depurar JavaScript, analisar requisições de rede e garantir conformidade de acessibilidade.
""",
        "keywords": "webview,desenvolvedor,debug,console,rede,safari,devtools,teste,inspetor,ios,javascript,html,cookie",
        "promotionalText": "Novo: Mac Agent permite ao seu agente de programação testar páginas no Walnut a partir do Mac. Com Console, Network e Sources integrados para depuração de WebView."
    },
    "ru": {
        "name": "Walnut: Webview Тест и Отладка",
        "subtitle": "WebView-отладка с ИИ-агентом",
        "description": """Идеальный инструмент разработчика для тестирования конфигураций WKWebView и SFSafariViewController в реальном времени.

MAC AGENT (НОВОЕ)
• Позвольте ИИ-агенту для кода или терминалу Mac управлять WKWebView в Walnut на вашем iPhone
• Открывайте страницы, нажимайте и вводите текст, запускайте скрипты и читайте логи Console и Network
• Выбирайте подтверждения: спрашивать каждый раз, разрешать действия на странице или разрешить всё
• Выполните сопряжение один раз по Wi-Fi или USB с 6-значным подтверждением

ОСНОВНЫЕ ФУНКЦИИ

Тестирование WKWebView
• Тестирование конфигурации в реальном времени с более чем 20 опциями
• Встроенные DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Инъекция JavaScript и выполнение сниппетов
• Эмуляция пользовательского User-Agent
• Эмуляция viewport и устройства

Тестирование SFSafariViewController
• Нативный опыт Safari с блокировщиками контента
• Reader Mode и адаптивное управление размером
• Настраиваемые цвета панели и стили кнопок

Инструменты разработчика
• Console: Захват console.log с поддержкой стилей CSS %c
• Network: Мониторинг запросов fetch/XHR с данными тайминга
• Storage: Просмотр/редактирование localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) и Navigation Timing
• Sources: Инспекция дерева DOM, таблицы стилей, скрипты
• Accessibility: Аудит доступности на основе axe-core

Дополнительные функции
• Управление закладками для быстрого доступа к URL
• Адаптивное изменение размера viewport (пресеты iPhone, iPad, Desktop)
• Захват скриншотов
• Обнаружение возможностей API
• Поддержка тёмного режима

Идеально подходит для iOS-разработчиков, которым нужно тестировать рендеринг веб-контента, отлаживать JavaScript, анализировать сетевые запросы и обеспечивать соответствие требованиям доступности.
""",
        "keywords": "webview,разработчик,отладка,консоль,сеть,safari,devtools,тест,инспектор,ios,javascript,html,css",
        "promotionalText": "Новое: Mac Agent позволяет ИИ-агенту для кода тестировать страницы в Walnut с Mac. А Console, Network и Sources помогают отлаживать WebView."
    },
    "ar-SA": {
        "name": "Walnut: Webview اختبار وتصحيح",
        "subtitle": "تصحيح WebView بالوكلاء",
        "description": """الأداة المثالية للمطورين لاختبار إعدادات WKWebView و SFSafariViewController في الوقت الفعلي.

MAC AGENT (جديد)
• اسمح لوكيل برمجة أو طرفية Mac لديك بالتحكم في WKWebView الخاص بـ Walnut على iPhone
• افتح الصفحات، انقر واكتب، شغّل السكربتات، واقرأ سجلات Console وNetwork
• اختر الموافقات: السؤال كل مرة، السماح بإجراءات الصفحة، أو السماح بكل شيء
• اقرن مرة واحدة عبر Wi-Fi أو USB بتأكيد من 6 أرقام

الميزات الرئيسية

اختبار WKWebView
• اختبار الإعدادات في الوقت الفعلي مع أكثر من 20 خياراً
• أدوات DevTools مدمجة: Console, Network, Storage, Performance, Sources, Accessibility
• حقن JavaScript وتنفيذ المقتطفات
• محاكاة User-Agent مخصصة
• محاكاة منفذ العرض والجهاز

اختبار SFSafariViewController
• تجربة Safari الأصلية مع حاجب المحتوى
• وضع القارئ والتحكم في الحجم المتجاوب
• ألوان الشريط وأنماط الأزرار القابلة للتخصيص

أدوات المطور
• Console: التقاط console.log مع دعم تنسيق CSS %c
• Network: مراقبة طلبات fetch/XHR مع بيانات التوقيت
• Storage: عرض/تحرير localStorage و sessionStorage وملفات تعريف الارتباط
• Performance: Web Vitals (LCP, FID, CLS) و Navigation Timing
• Sources: فحص شجرة DOM وأوراق الأنماط والبرامج النصية
• Accessibility: تدقيق إمكانية الوصول بناءً على axe-core

ميزات إضافية
• إدارة الإشارات المرجعية للوصول السريع لعناوين URL
• تغيير حجم منفذ العرض التكيفي (إعدادات iPhone و iPad و Desktop)
• التقاط لقطات الشاشة
• اكتشاف قدرات API
• دعم الوضع الداكن

مثالية لمطوري iOS الذين يحتاجون إلى اختبار عرض محتوى الويب وتصحيح أخطاء JavaScript وتحليل طلبات الشبكة وضمان الامتثال لإمكانية الوصول.
""",
        "keywords": "webview,مطور,تصحيح,وحدة التحكم,شبكة,safari,devtools,اختبار,فحص,ios,javascript,html,css,متصفح,أداة",
        "promotionalText": "جديد: Mac Agent يتيح لوكيل البرمجة اختبار الصفحات في Walnut من Mac. مع Console وNetwork وSources مدمجة لتصحيح WebView."
    },
    "hi": {
        "name": "Walnut: Webview टेस्ट और डीबग",
        "subtitle": "एजेंट से WebView डिबगिंग",
        "description": """WKWebView और SFSafariViewController कॉन्फ़िगरेशन को रीयल-टाइम में टेस्ट करने के लिए परम डेवलपर टूल।

MAC AGENT (नया)
• अपने कोडिंग एजेंट या Mac टर्मिनल को आपके iPhone पर Walnut के WKWebView को नियंत्रित करने दें
• पेज खोलें, टैप और टाइप करें, स्क्रिप्ट चलाएँ, और Console व Network लॉग पढ़ें
• अनुमतियाँ चुनें: हर बार पूछें, पेज क्रियाओं की अनुमति दें, या सब कुछ करने दें
• 6-अंकीय पुष्टि के साथ Wi-Fi या USB पर एक बार पेयर करें

मुख्य विशेषताएं

WKWebView टेस्टिंग
• 20+ विकल्पों के साथ रीयल-टाइम कॉन्फ़िगरेशन टेस्टिंग
• बिल्ट-इन DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript इंजेक्शन और स्निपेट निष्पादन
• कस्टम User-Agent एमुलेशन
• व्यूपोर्ट और डिवाइस एमुलेशन

SFSafariViewController टेस्टिंग
• कंटेंट ब्लॉकर्स के साथ नेटिव Safari अनुभव
• Reader Mode और रिस्पॉन्सिव साइज़ कंट्रोल
• कस्टमाइज़ेबल बार कलर और बटन स्टाइल

डेवलपर टूल्स
• Console: %c CSS स्टाइलिंग सपोर्ट के साथ console.log कैप्चर
• Network: टाइमिंग डेटा के साथ fetch/XHR रिक्वेस्ट मॉनिटर करें
• Storage: localStorage, sessionStorage, cookies देखें/संपादित करें
• Performance: Web Vitals (LCP, FID, CLS) और Navigation Timing
• Sources: DOM ट्री इंस्पेक्शन, स्टाइलशीट्स, स्क्रिप्ट्स
• Accessibility: axe-core आधारित एक्सेसिबिलिटी ऑडिटिंग

अतिरिक्त विशेषताएं
• त्वरित URL एक्सेस के लिए बुकमार्क प्रबंधन
• रेस्पॉन्सिव व्यूपोर्ट रीसाइज़िंग (iPhone, iPad, Desktop प्रीसेट)
• स्क्रीनशॉट कैप्चर
• API क्षमता पहचान
• डार्क मोड सपोर्ट

iOS डेवलपर्स के लिए परफेक्ट जिन्हें वेब कंटेंट रेंडरिंग टेस्ट करना है, JavaScript डीबग करना है, नेटवर्क रिक्वेस्ट एनालाइज़ करना है और एक्सेसिबिलिटी कंप्लायंस सुनिश्चित करना है।
""",
        "keywords": "webview,डेवलपर,डीबग,कंसोल,नेटवर्क,safari,devtools,टेस्ट,इंस्पेक्ट,ios,javascript,html,css,ब्राउज़र",
        "promotionalText": "नया: Mac Agent आपके कोडिंग एजेंट को Mac से Walnut में पेज टेस्ट करने देता है। WebView डीबगिंग के लिए Console, Network, Sources भी।"
    },
    "th": {
        "name": "Walnut: Webview ทดสอบและดีบัก",
        "subtitle": "ดีบัก WebView ด้วยเอเจนต์",
        "description": """เครื่องมือสำหรับนักพัฒนาเพื่อทดสอบการกำหนดค่า WKWebView และ SFSafariViewController แบบเรียลไทม์

MAC AGENT (ใหม่)
• ให้เอเจนต์เขียนโค้ดหรือ terminal บน Mac ของคุณสั่งงาน WKWebView ของ Walnut บน iPhone
• เปิดหน้า แตะและพิมพ์ รันสคริปต์ และอ่านบันทึก Console และ Network
• เลือกการอนุมัติ: ถามทุกครั้ง อนุญาตการทำงานบนหน้า หรืออนุญาตทั้งหมด
• จับคู่ครั้งเดียวผ่าน Wi-Fi หรือ USB พร้อมการยืนยัน 6 หลัก

คุณสมบัติหลัก

การทดสอบ WKWebView
• การทดสอบการกำหนดค่าแบบเรียลไทม์พร้อมตัวเลือกกว่า 20 รายการ
• DevTools ในตัว: Console, Network, Storage, Performance, Sources, Accessibility
• การฉีด JavaScript และการรันโค้ดสั้น
• การจำลอง User-Agent แบบกำหนดเอง
• การจำลอง Viewport และอุปกรณ์

การทดสอบ SFSafariViewController
• ประสบการณ์ Safari ดั้งเดิมพร้อม Content Blockers
• Reader Mode และการควบคุมขนาดแบบ Responsive
• สีแถบและสไตล์ปุ่มที่ปรับแต่งได้

เครื่องมือสำหรับนักพัฒนา
• Console: จับ console.log พร้อมรองรับการจัดรูปแบบ CSS %c
• Network: ตรวจสอบคำขอ fetch/XHR พร้อมข้อมูลเวลา
• Storage: ดู/แก้ไข localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) และ Navigation Timing
• Sources: ตรวจสอบ DOM tree, สไตล์ชีต, สคริปต์
• Accessibility: การตรวจสอบการเข้าถึงตาม axe-core

คุณสมบัติเพิ่มเติม
• การจัดการบุ๊กมาร์กสำหรับการเข้าถึง URL อย่างรวดเร็ว
• การปรับขนาด Viewport แบบตอบสนอง (พรีเซ็ต iPhone, iPad, Desktop)
• การจับภาพหน้าจอ
• การตรวจจับความสามารถของ API
• รองรับโหมดมืด

เหมาะสำหรับนักพัฒนา iOS ที่ต้องการทดสอบการแสดงผลเนื้อหาเว็บ ดีบัก JavaScript วิเคราะห์คำขอเครือข่าย และรับรองการปฏิบัติตามการเข้าถึง
""",
        "keywords": "webview,นักพัฒนา,ดีบัก,คอนโซล,เครือข่าย,safari,devtools,ทดสอบ,ตรวจสอบ,ios,javascript,html,css",
        "promotionalText": "ใหม่: Mac Agent ให้เอเจนต์เขียนโค้ดทดสอบหน้าใน Walnut จาก Mac ของคุณ พร้อม Console, Network และ Sources ในตัวสำหรับดีบัก WebView"
    },
    "vi": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Gỡ lỗi WebView bằng agent",
        "description": """Công cụ dành cho nhà phát triển để kiểm thử cấu hình WKWebView và SFSafariViewController theo thời gian thực.

MAC AGENT (MỚI)
• Cho phép coding agent hoặc terminal trên Mac điều khiển WKWebView của Walnut trên iPhone
• Mở trang, chạm và nhập, chạy script, và đọc nhật ký Console và Network
• Chọn phê duyệt: hỏi mỗi lần, cho phép thao tác trên trang, hoặc cho phép mọi thứ
• Ghép đôi một lần qua Wi-Fi hoặc USB với xác nhận 6 chữ số

TÍNH NĂNG CHÍNH

Kiểm thử WKWebView
• Kiểm thử cấu hình thời gian thực với hơn 20 tùy chọn
• DevTools tích hợp: Console, Network, Storage, Performance, Sources, Accessibility
• Tiêm JavaScript và thực thi đoạn mã
• Giả lập User-Agent tùy chỉnh
• Giả lập viewport và thiết bị

Kiểm thử SFSafariViewController
• Trải nghiệm Safari gốc với trình chặn nội dung
• Reader Mode và điều khiển kích thước responsive
• Màu thanh và kiểu nút có thể tùy chỉnh

Công cụ phát triển
• Console: Ghi nhận console.log với hỗ trợ định dạng CSS %c
• Network: Giám sát yêu cầu fetch/XHR với dữ liệu thời gian
• Storage: Xem/chỉnh sửa localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) và Navigation Timing
• Sources: Kiểm tra cây DOM, stylesheet, script
• Accessibility: Kiểm tra khả năng truy cập dựa trên axe-core

Tính năng bổ sung
• Quản lý bookmark để truy cập URL nhanh
• Thay đổi kích thước viewport đáp ứng (preset iPhone, iPad, Desktop)
• Chụp ảnh màn hình
• Phát hiện khả năng API
• Hỗ trợ chế độ tối

Hoàn hảo cho các nhà phát triển iOS cần kiểm thử hiển thị nội dung web, gỡ lỗi JavaScript, phân tích yêu cầu mạng và đảm bảo tuân thủ khả năng truy cập.
""",
        "keywords": "webview,lập trình,debug,console,mạng,safari,devtools,kiểm thử,kiểm tra,ios,javascript,html,css",
        "promotionalText": "Mới: Mac Agent cho phép coding agent kiểm thử trang trong Walnut từ Mac. Có sẵn Console, Network và Sources để gỡ lỗi WebView."
    },
    "id": {
        "name": "Walnut: Webview Tes & Debug",
        "subtitle": "Debugging WebView dengan Agen",
        "description": """Alat pengembang terbaik untuk menguji konfigurasi WKWebView dan SFSafariViewController secara real-time.

MAC AGENT (BARU)
• Biarkan agen coding atau terminal Mac Anda mengendalikan WKWebView Walnut di iPhone Anda
• Buka halaman, ketuk dan ketik, jalankan skrip, serta baca log Console dan Network
• Pilih persetujuan: tanya setiap kali, izinkan tindakan halaman, atau izinkan semuanya
• Pasangkan sekali melalui Wi-Fi atau USB dengan konfirmasi 6 digit

FITUR UTAMA

Pengujian WKWebView
• Pengujian konfigurasi real-time dengan lebih dari 20 opsi
• DevTools bawaan: Console, Network, Storage, Performance, Sources, Accessibility
• Injeksi JavaScript dan eksekusi snippet
• Emulasi User-Agent kustom
• Emulasi viewport dan perangkat

Pengujian SFSafariViewController
• Pengalaman Safari native dengan pemblokir konten
• Reader Mode dan kontrol ukuran responsif
• Warna bar dan gaya tombol yang dapat disesuaikan

Alat Pengembang
• Console: Tangkap console.log dengan dukungan styling CSS %c
• Network: Monitor permintaan fetch/XHR dengan data timing
• Storage: Lihat/edit localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) dan Navigation Timing
• Sources: Inspeksi pohon DOM, stylesheet, skrip
• Accessibility: Audit aksesibilitas berbasis axe-core

Fitur Tambahan
• Manajemen bookmark untuk akses URL cepat
• Pengubahan ukuran viewport responsif (preset iPhone, iPad, Desktop)
• Tangkapan layar
• Deteksi kemampuan API
• Dukungan mode gelap

Sempurna untuk pengembang iOS yang perlu menguji rendering konten web, debug JavaScript, menganalisis permintaan jaringan, dan memastikan kepatuhan aksesibilitas.
""",
        "keywords": "webview,developer,debug,console,jaringan,safari,devtools,tes,inspeksi,ios,javascript,html,css",
        "promotionalText": "Baru: Mac Agent memungkinkan agen coding menguji halaman di Walnut dari Mac. Serta Console, Network, dan Sources bawaan untuk debugging WebView."
    },
    "ms": {
        "name": "Walnut: Webview Uji & Nyahpepijat",
        "subtitle": "Nyahpepijat WebView dgn Ejen",
        "description": """Alat pembangun terbaik untuk menguji konfigurasi WKWebView dan SFSafariViewController secara masa nyata.

MAC AGENT (BARU)
• Benarkan ejen pengekodan atau terminal Mac anda mengawal WKWebView Walnut pada iPhone anda
• Buka halaman, ketik dan taip, jalankan skrip, serta baca log Console dan Network
• Pilih kelulusan: tanya setiap kali, benarkan tindakan halaman, atau benarkan semuanya
• Pasangkan sekali melalui Wi-Fi atau USB dengan pengesahan 6 digit

CIRI-CIRI UTAMA

Pengujian WKWebView
• Pengujian konfigurasi masa nyata dengan lebih dari 20 pilihan
• DevTools terbina dalam: Console, Network, Storage, Performance, Sources, Accessibility
• Suntikan JavaScript dan pelaksanaan snippet
• Emulasi User-Agent tersuai
• Emulasi viewport dan peranti

Pengujian SFSafariViewController
• Pengalaman Safari asli dengan penyekat kandungan
• Reader Mode dan kawalan saiz responsif
• Warna bar dan gaya butang yang boleh disesuaikan

Alat Pembangun
• Console: Tangkap console.log dengan sokongan gaya CSS %c
• Network: Pantau permintaan fetch/XHR dengan data masa
• Storage: Lihat/edit localStorage, sessionStorage, kuki
• Performance: Web Vitals (LCP, FID, CLS) dan Navigation Timing
• Sources: Pemeriksaan pokok DOM, helaian gaya, skrip
• Accessibility: Audit kebolehcapaian berasaskan axe-core

Ciri-ciri Tambahan
• Pengurusan penanda buku untuk akses URL pantas
• Pengubahsuaian saiz viewport responsif (pratetap iPhone, iPad, Desktop)
• Tangkapan skrin
• Pengesanan keupayaan API
• Sokongan mod gelap

Sempurna untuk pembangun iOS yang perlu menguji pemaparan kandungan web, nyahpepijat JavaScript, menganalisis permintaan rangkaian, dan memastikan pematuhan kebolehcapaian.
""",
        "keywords": "webview,pembangun,debug,konsol,rangkaian,safari,devtools,uji,periksa,ios,javascript,html,css,pelayar",
        "promotionalText": "Baru: Mac Agent membolehkan ejen pengekodan anda menguji halaman dalam Walnut dari Mac. Console, Network dan Sources terbina untuk nyahpepijat WebView."
    },
    "nl-NL": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Agentisch WebView-debuggen",
        "description": """De ultieme ontwikkelaarstool voor het testen van WKWebView- en SFSafariViewController-configuraties in realtime.

MAC AGENT (NIEUW)
• Laat een codeeragent of je Mac-terminal Walnut's WKWebView op je iPhone aansturen
• Open pagina's, tik en typ, voer scripts uit en lees Console- en Network-logboeken
• Kies goedkeuringen: vraag elke keer, sta pagina-acties toe of sta alles toe
• Koppel één keer via Wi-Fi of USB met een 6-cijferige bevestiging

BELANGRIJKSTE FUNCTIES

WKWebView-testen
• Realtime configuratietesten met meer dan 20 opties
• Ingebouwde DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-injectie en snippet-uitvoering
• Aangepaste User-Agent-emulatie
• Viewport- en apparaatemulatie

SFSafariViewController-testen
• Native Safari-ervaring met contentblockers
• Reader Mode en responsieve groottecontrole
• Aanpasbare balkkleuren en knopstijlen

Ontwikkelaarstools
• Console: console.log-vastlegging met %c CSS-styling-ondersteuning
• Network: Fetch/XHR-verzoeken monitoren met timinggegevens
• Storage: localStorage, sessionStorage, cookies bekijken/bewerken
• Performance: Web Vitals (LCP, FID, CLS) en Navigation Timing
• Sources: DOM-boominspectie, stylesheets, scripts
• Accessibility: axe-core-gebaseerde toegankelijkheidsaudit

Extra functies
• Bladwijzerbeheer voor snelle URL-toegang
• Responsieve viewportgrootte (iPhone, iPad, Desktop-presets)
• Schermafbeelding
• API-mogelijkheidsdetectie
• Ondersteuning voor donkere modus

Perfect voor iOS-ontwikkelaars die webcontent-rendering moeten testen, JavaScript moeten debuggen, netwerkverzoeken moeten analyseren en toegankelijkheidsconformiteit moeten waarborgen.
""",
        "keywords": "webview,ontwikkelaar,debug,console,netwerk,safari,devtools,test,inspecteer,ios,javascript,html,css",
        "promotionalText": "Nieuw: Mac Agent laat je codeeragent pagina's testen in Walnut vanaf je Mac. Met Console, Network en Sources voor WebView-debugging."
    },
    "pl": {
        "name": "Walnut: Webview Test i Debug",
        "subtitle": "Debugowanie WebView z agentem",
        "description": """Najlepsze narzędzie deweloperskie do testowania konfiguracji WKWebView i SFSafariViewController w czasie rzeczywistym.

MAC AGENT (NOWOŚĆ)
• Pozwól agentowi kodu lub terminalowi na Mac sterować WKWebView Walnut na iPhone
• Otwieraj strony, stukaj i wpisuj tekst, uruchamiaj skrypty oraz czytaj logi Console i Network
• Wybierz zatwierdzenia: pytaj za każdym razem, zezwalaj na działania na stronie albo zezwalaj na wszystko
• Sparuj raz przez Wi-Fi lub USB z 6-cyfrowym potwierdzeniem

GŁÓWNE FUNKCJE

Testowanie WKWebView
• Testowanie konfiguracji w czasie rzeczywistym z ponad 20 opcjami
• Wbudowane DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Wstrzykiwanie JavaScript i wykonywanie snippetów
• Emulacja niestandardowego User-Agent
• Emulacja viewport i urządzenia

Testowanie SFSafariViewController
• Natywne doświadczenie Safari z blokerami treści
• Reader Mode i responsywna kontrola rozmiaru
• Konfigurowalne kolory paska i style przycisków

Narzędzia deweloperskie
• Console: Przechwytywanie console.log z obsługą stylowania CSS %c
• Network: Monitorowanie żądań fetch/XHR z danymi czasowymi
• Storage: Przeglądanie/edycja localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) i Navigation Timing
• Sources: Inspekcja drzewa DOM, arkusze stylów, skrypty
• Accessibility: Audyt dostępności oparty na axe-core

Dodatkowe funkcje
• Zarządzanie zakładkami dla szybkiego dostępu do URL
• Responsywna zmiana rozmiaru viewport (presety iPhone, iPad, Desktop)
• Przechwytywanie zrzutów ekranu
• Wykrywanie możliwości API
• Obsługa trybu ciemnego

Idealne dla programistów iOS, którzy muszą testować renderowanie treści webowych, debugować JavaScript, analizować żądania sieciowe i zapewniać zgodność z dostępnością.
""",
        "keywords": "webview,programista,debug,konsola,sieć,safari,devtools,test,inspektor,ios,javascript,html,css",
        "promotionalText": "Nowość: Mac Agent pozwala testować strony w Walnut z poziomu Mac. Wbudowane Console, Network i Sources do debugowania WebView."
    },
    "tr": {
        "name": "Walnut: Webview Test & Hata Ayıklama",
        "subtitle": "Ajanla WebView Hata Ayıklama",
        "description": """WKWebView ve SFSafariViewController yapılandırmalarını gerçek zamanlı test etmek için nihai geliştirici aracı.

MAC AGENT (YENİ)
• Bir kodlama aracısının veya Mac terminalinizin iPhone’unuzda Walnut WKWebView’ını kontrol etmesini sağlayın
• Sayfaları açın, dokunun ve yazın, betikler çalıştırın, Console ve Network günlüklerini okuyun
• Onayları seçin: her seferinde sor, sayfa eylemlerine izin ver veya her şeye izin ver
• Wi-Fi veya USB üzerinden 6 haneli onayla bir kez eşleyin

ANA ÖZELLİKLER

WKWebView Testi
• 20'den fazla seçenekle gerçek zamanlı yapılandırma testi
• Yerleşik DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript enjeksiyonu ve snippet çalıştırma
• Özel User-Agent emülasyonu
• Viewport ve cihaz emülasyonu

SFSafariViewController Testi
• İçerik engelleyicilerle yerel Safari deneyimi
• Reader Mode ve duyarlı boyut kontrolü
• Özelleştirilebilir çubuk renkleri ve düğme stilleri

Geliştirici Araçları
• Console: %c CSS stilleme desteğiyle console.log yakalama
• Network: Zamanlama verileriyle fetch/XHR isteklerini izleme
• Storage: localStorage, sessionStorage, çerezleri görüntüleme/düzenleme
• Performance: Web Vitals (LCP, FID, CLS) ve Navigation Timing
• Sources: DOM ağacı incelemesi, stil sayfaları, scriptler
• Accessibility: axe-core tabanlı erişilebilirlik denetimi

Ek Özellikler
• Hızlı URL erişimi için yer imi yönetimi
• Duyarlı viewport boyutlandırma (iPhone, iPad, Desktop önayarları)
• Ekran görüntüsü yakalama
• API yetenek algılama
• Karanlık mod desteği

Web içerik görüntülemeyi test etmesi, JavaScript hata ayıklaması, ağ isteklerini analiz etmesi ve erişilebilirlik uyumluluğunu sağlaması gereken iOS geliştiricileri için mükemmel.
""",
        "keywords": "webview,geliştirici,debug,konsol,ağ,safari,devtools,test,denetim,ios,javascript,html,css,tarayıcı",
        "promotionalText": "Yeni: Mac Agent ile kodlama aracınız Mac’inizden Walnut’ta sayfaları test eder. WebView hata ayıklama için Console, Network ve Sources yerleşik."
    },
    "uk": {
        "name": "Walnut: Webview Тест і Налагодження",
        "subtitle": "WebView-налагодження з агентом",
        "description": """Найкращий інструмент розробника для тестування конфігурацій WKWebView та SFSafariViewController в реальному часі.

MAC AGENT (НОВЕ)
• Дозвольте агенту кодування або терміналу Mac керувати WKWebView у Walnut на вашому iPhone
• Відкривайте сторінки, натискайте й вводьте текст, запускайте скрипти та читайте журнали Console і Network
• Обирайте схвалення: запит щоразу, дозвіл на дії на сторінці або дозвіл на все
• Створіть пару один раз через Wi-Fi або USB із 6-значним підтвердженням

ОСНОВНІ ФУНКЦІЇ

Тестування WKWebView
• Тестування конфігурації в реальному часі з понад 20 опціями
• Вбудовані DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Інʼєкція JavaScript та виконання сніппетів
• Емуляція користувацького User-Agent
• Емуляція viewport та пристрою

Тестування SFSafariViewController
• Нативний досвід Safari з блокувальниками контенту
• Reader Mode та адаптивне керування розміром
• Налаштовувані кольори панелі та стилі кнопок

Інструменти розробника
• Console: Захоплення console.log з підтримкою стилів CSS %c
• Network: Моніторинг запитів fetch/XHR з даними тайминга
• Storage: Перегляд/редагування localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) та Navigation Timing
• Sources: Інспекція дерева DOM, таблиці стилів, скрипти
• Accessibility: Аудит доступності на основі axe-core

Додаткові функції
• Керування закладками для швидкого доступу до URL
• Адаптивна зміна розміру viewport (пресети iPhone, iPad, Desktop)
• Захоплення скріншотів
• Виявлення можливостей API
• Підтримка темного режиму

Ідеально підходить для iOS-розробників, яким потрібно тестувати рендеринг веб-контенту, налагоджувати JavaScript, аналізувати мережеві запити та забезпечувати відповідність вимогам доступності.
""",
        "keywords": "webview,розробник,налагодження,консоль,мережа,safari,devtools,тест,інспектор,ios,javascript,html",
        "promotionalText": "Нове: Mac Agent дає агенту кодування тестувати сторінки в Walnut із Mac. А Console, Network і Sources вже вбудовані для налагодження WebView."
    },
    "sv": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Agentisk WebView-felsökning",
        "description": """Det ultimata utvecklarverktyget för att testa WKWebView- och SFSafariViewController-konfigurationer i realtid.

MAC AGENT (NY)
• Låt en kodagent eller din Mac-terminal styra WKWebView i Walnut på din iPhone
• Öppna sidor, tryck och skriv, kör skript och läs loggar i Console och Network
• Välj godkännanden: fråga varje gång, tillåt sidåtgärder eller tillåt allt
• Parkoppla en gång via Wi-Fi eller USB med en 6-siffrig bekräftelse

HUVUDFUNKTIONER

WKWebView-testning
• Realtidskonfigurationstestning med över 20 alternativ
• Inbyggda DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-injektion och snippet-körning
• Anpassad User-Agent-emulering
• Viewport- och enhetsemulering

SFSafariViewController-testning
• Native Safari-upplevelse med innehållsblockerare
• Reader Mode och responsiv storlekskontroll
• Anpassningsbara fältfärger och knappformat

Utvecklarverktyg
• Console: console.log-fångst med %c CSS-stilstöd
• Network: Övervaka fetch/XHR-förfrågningar med tidsdata
• Storage: Visa/redigera localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) och Navigation Timing
• Sources: DOM-trädinspektion, stilmallar, skript
• Accessibility: axe-core-baserad tillgänglighetsrevision

Ytterligare funktioner
• Bokmärkeshantering för snabb URL-åtkomst
• Responsiv viewportstorleksändring (iPhone, iPad, Desktop-förinställningar)
• Skärmdumpsfångst
• API-kapacitetsdetektering
• Stöd för mörkt läge

Perfekt för iOS-utvecklare som behöver testa webbinnehållsrendering, felsöka JavaScript, analysera nätverksförfrågningar och säkerställa tillgänglighetsefterlevnad.
""",
        "keywords": "webview,utvecklare,debug,konsol,nätverk,safari,devtools,test,inspektera,ios,javascript,html,css",
        "promotionalText": "Nytt: Mac Agent låter din kodagent testa sidor i Walnut från din Mac. Console, Network och Sources ingår för WebView-felsökning."
    },
    "no": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Agentisk WebView-feilsøking",
        "description": """Det ultimate utviklerverktøyet for testing av WKWebView- og SFSafariViewController-konfigurasjoner i sanntid.

MAC AGENT (NY)
• La en kodeagent eller terminalen på Mac styre WKWebView i Walnut på iPhone
• Åpne sider, trykk og skriv, kjør skript, og les Console- og Network-logger
• Velg godkjenninger: spør hver gang, tillat sidehandlinger eller tillat alt
• Par én gang via Wi-Fi eller USB med en sekssifret bekreftelse

HOVEDFUNKSJONER

WKWebView-testing
• Sanntidskonfigurasjonstesting med over 20 alternativer
• Innebygde DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-injeksjon og snippet-kjøring
• Tilpasset User-Agent-emulering
• Viewport- og enhetsemulering

SFSafariViewController-testing
• Native Safari-opplevelse med innholdsblokkere
• Reader Mode og responsiv størrelseskontroll
• Tilpassbare feltfarger og knappstiler

Utviklerverktøy
• Console: console.log-fangst med %c CSS-stilstøtte
• Network: Overvåk fetch/XHR-forespørsler med tidsdata
• Storage: Vis/rediger localStorage, sessionStorage, informasjonskapsler
• Performance: Web Vitals (LCP, FID, CLS) og Navigation Timing
• Sources: DOM-treinspeksjon, stilark, skript
• Accessibility: axe-core-basert tilgjengelighetsrevisjon

Ytterligere funksjoner
• Bokmerkebehandling for rask URL-tilgang
• Responsiv viewportstørrelsesendring (iPhone, iPad, Desktop-forhåndsinnstillinger)
• Skjermbilde-fangst
• API-kapasitetsdeteksjon
• Støtte for mørk modus

Perfekt for iOS-utviklere som trenger å teste webinnholdsrendering, feilsøke JavaScript, analysere nettverksforespørsler og sikre tilgjengelighetsoverholdelse.
""",
        "keywords": "webview,utvikler,debug,konsoll,nettverk,safari,devtools,test,inspiser,ios,javascript,html,css",
        "promotionalText": "Nytt: Mac Agent lar kodeagenten teste sider i Walnut fra Mac. Med Console, Network og Sources innebygd for WebView-feilsøking."
    },
    "da": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Agentisk WebView-fejlfinding",
        "description": """Det ultimative udviklerværktøj til test af WKWebView- og SFSafariViewController-konfigurationer i realtid.

MAC AGENT (NY)
• Lad en kodeagent eller din Mac-terminal styre Walnut's WKWebView på din iPhone
• Åbn sider, tryk og skriv, kør scripts, og læs Console- og Network-logfiler
• Vælg godkendelser: spørg hver gang, tillad sidehandlinger, eller tillad alt
• Par én gang via Wi-Fi eller USB med en 6-cifret bekræftelse

HOVEDFUNKTIONER

WKWebView-test
• Realtidskonfigurationstest med over 20 muligheder
• Indbyggede DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-injektion og snippet-kørsel
• Tilpasset User-Agent-emulering
• Viewport- og enhedsemulering

SFSafariViewController-test
• Native Safari-oplevelse med indholdsblokkere
• Reader Mode og responsiv størrelseskontrol
• Tilpasselige bjælkefarver og knapstile

Udviklerværktøjer
• Console: console.log-optagelse med %c CSS-stilunderstøttelse
• Network: Overvåg fetch/XHR-anmodninger med tidsdata
• Storage: Vis/rediger localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) og Navigation Timing
• Sources: DOM-træinspektion, stilark, scripts
• Accessibility: axe-core-baseret tilgængelighedsrevision

Yderligere funktioner
• Bogmærkestyring til hurtig URL-adgang
• Responsiv viewport-størrelse (iPhone, iPad, Desktop-forudindstillinger)
• Skærmbillede
• API-kapacitetsdetektion
• Understøttelse af mørk tilstand

Perfekt til iOS-udviklere, der skal teste webindholdsgengivelse, debugge JavaScript, analysere netværksanmodninger og sikre tilgængelighedsoverholdelse.
""",
        "keywords": "webview,udvikler,debug,konsol,netværk,safari,devtools,test,inspicér,ios,javascript,html,css,browser",
        "promotionalText": "Nyt: Mac Agent lader din kodeagent teste sider i Walnut fra din Mac. Plus Console, Network og Sources indbygget til WebView-fejlfinding."
    },
    "fi": {
        "name": "Walnut: Webview Testi & Debug",
        "subtitle": "WebView-vianetsintä agentilla",
        "description": """Kehittäjätyökalu WKWebView- ja SFSafariViewController-konfiguraatioiden reaaliaikaiseen testaamiseen.

MAC AGENT (UUSI)
• Anna koodausagentin tai Mac-päätteesi ohjata Walnutin WKWebView'ta iPhone-laitteellasi
• Avaa sivuja, napauta ja kirjoita, suorita skriptejä sekä lue Console- ja Network-lokeja
• Valitse hyväksynnät: kysy joka kerta, salli sivutoiminnot tai salli kaikki
• Muodosta pari kerran Wi-Fi- tai USB-yhteydellä 6-numeroisella vahvistuksella

PÄÄOMINAISUUDET

WKWebView-testaus
• Reaaliaikainen konfiguraatiotestaus yli 20 vaihtoehdolla
• Sisäänrakennetut DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript-injektio ja snippet-suoritus
• Mukautettu User-Agent-emulointi
• Viewport- ja laiteemulointi

SFSafariViewController-testaus
• Natiivi Safari-kokemus sisällönestäjillä
• Reader Mode ja responsiivinen kokohallinta
• Mukautettavat palkkivärit ja painiketyylit

Kehittäjätyökalut
• Console: console.log-kaappaus %c CSS-tyylituella
• Network: Fetch/XHR-pyyntöjen seuranta ajoitustiedoilla
• Storage: localStorage-, sessionStorage-, evästeiden katselu/muokkaus
• Performance: Web Vitals (LCP, FID, CLS) ja Navigation Timing
• Sources: DOM-puun tarkastus, tyylisivut, skriptit
• Accessibility: axe-core-pohjainen saavutettavuustarkastus

Lisäominaisuudet
• Kirjanmerkkien hallinta nopeaan URL-käyttöön
• Responsiivinen viewport-koon muuttaminen (iPhone, iPad, Desktop-esiasetukset)
• Kuvakaappaus
• API-ominaisuuksien tunnistus
• Tumman tilan tuki

Täydellinen iOS-kehittäjille, jotka tarvitsevat web-sisällön renderöinnin testausta, JavaScript-virheenkorjausta, verkkopyyntöjen analysointia ja saavutettavuusvaatimusten varmistamista.
""",
        "keywords": "webview,kehittäjä,debug,konsoli,verkko,safari,devtools,testi,tarkasta,ios,javascript,html,css,selain",
        "promotionalText": "Uusi: Mac Agent antaa koodausagenttisi testata sivuja Walnutissa Maciltasi. Console, Network ja Sources sisäänrakennettuina WebView-vianetsintään."
    },
    "cs": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Ladění WebView s agentem",
        "description": """Ultimátní vývojářský nástroj pro testování konfigurací WKWebView a SFSafariViewController v reálném čase.

MAC AGENT (NOVÉ)
• Nechte programovacího agenta nebo terminál na Mac ovládat WKWebView ve Walnut na vašem iPhone
• Otevírejte stránky, klepejte a pište, spouštějte skripty a čtěte logy Console a Network
• Zvolte schvalování: ptát se pokaždé, povolit akce na stránce nebo povolit vše
• Spárujte jednou přes Wi-Fi nebo USB s 6místným potvrzením

HLAVNÍ FUNKCE

Testování WKWebView
• Testování konfigurace v reálném čase s více než 20 možnostmi
• Vestavěné DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Injekce JavaScriptu a spouštění snippetů
• Emulace vlastního User-Agent
• Emulace viewportu a zařízení

Testování SFSafariViewController
• Nativní Safari zážitek s blokátory obsahu
• Reader Mode a responzivní ovládání velikosti
• Přizpůsobitelné barvy lišty a styly tlačítek

Vývojářské nástroje
• Console: Zachycení console.log s podporou %c CSS stylování
• Network: Monitorování fetch/XHR požadavků s časovými daty
• Storage: Zobrazení/úprava localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) a Navigation Timing
• Sources: Inspekce DOM stromu, styly, skripty
• Accessibility: Audit přístupnosti založený na axe-core

Další funkce
• Správa záložek pro rychlý přístup k URL
• Responzivní změna velikosti viewportu (presety iPhone, iPad, Desktop)
• Zachycení snímku obrazovky
• Detekce schopností API
• Podpora tmavého režimu

Ideální pro iOS vývojáře, kteří potřebují testovat vykreslování webového obsahu, debugovat JavaScript, analyzovat síťové požadavky a zajistit soulad s přístupností.
""",
        "keywords": "webview,vývojář,debug,konzole,síť,safari,devtools,test,inspektor,ios,javascript,html,css,prohlížeč",
        "promotionalText": "Novinka: Mac Agent umožní programovacímu agentovi testovat stránky ve Walnut z Mac. Console, Network a Sources jsou vestavěné pro ladění WebView."
    },
    "sk": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Ladenie WebView s agentom",
        "description": """Ultimátny vývojársky nástroj pre testovanie konfigurácií WKWebView a SFSafariViewController v reálnom čase.

MAC AGENT (NOVÉ)
• Nechajte agenta na kódovanie alebo terminál na Mac ovládať WKWebView vo Walnut na vašom iPhone
• Otvárajte stránky, ťukajte a píšte, spúšťajte skripty a čítajte záznamy Console a Network
• Vyberte schvaľovanie: pýtať sa vždy, povoliť akcie na stránke alebo povoliť všetko
• Spárujte raz cez Wi-Fi alebo USB pomocou 6-miestneho potvrdenia

HLAVNÉ FUNKCIE

Testovanie WKWebView
• Testovanie konfigurácie v reálnom čase s viac ako 20 možnosťami
• Vstavané DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Injekcia JavaScriptu a spúšťanie snippetov
• Emulácia vlastného User-Agent
• Emulácia viewportu a zariadenia

Testovanie SFSafariViewController
• Natívny Safari zážitok s blokátormi obsahu
• Reader Mode a responzívne ovládanie veľkosti
• Prispôsobiteľné farby lišty a štýly tlačidiel

Vývojárske nástroje
• Console: Zachytenie console.log s podporou %c CSS štýlovania
• Network: Monitorovanie fetch/XHR požiadaviek s časovými údajmi
• Storage: Zobrazenie/úprava localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) a Navigation Timing
• Sources: Inšpekcia DOM stromu, štýly, skripty
• Accessibility: Audit prístupnosti založený na axe-core

Ďalšie funkcie
• Správa záložiek pre rýchly prístup k URL
• Responzívna zmena veľkosti viewportu (presety iPhone, iPad, Desktop)
• Zachytenie snímky obrazovky
• Detekcia schopností API
• Podpora tmavého režimu

Ideálne pre iOS vývojárov, ktorí potrebujú testovať vykresľovanie webového obsahu, debugovať JavaScript, analyzovať sieťové požiadavky a zabezpečiť súlad s prístupnosťou.
""",
        "keywords": "webview,vývojár,debug,konzola,sieť,safari,devtools,test,inšpektor,ios,javascript,html,css,prehliadač",
        "promotionalText": "Novinka: Mac Agent umožní agentovi na kódovanie testovať stránky vo Walnut z Mac. Plus Console, Network a Sources na ladenie WebView."
    },
    "hu": {
        "name": "Walnut: Webview Teszt & Debug",
        "subtitle": "WebView-hibakeresés ügynökkel",
        "description": """A tökéletes fejlesztői eszköz a WKWebView és SFSafariViewController konfigurációk valós idejű teszteléséhez.

MAC AGENT (ÚJ)
• Hagyd, hogy egy kódoló agent vagy a Mac terminálod vezérelje a Walnut WKWebView-ját az iPhone-odon
• Nyiss meg oldalakat, koppints és gépelj, futtass scripteket, és olvasd a Console és Network naplókat
• Válassz jóváhagyást: kérdezzen rá mindig, engedélyezze az oldalműveleteket, vagy engedélyezzen mindent
• Párosítsd egyszer Wi-Fi vagy USB kapcsolaton, 6 jegyű megerősítéssel

FŐ JELLEMZŐK

WKWebView tesztelés
• Valós idejű konfigurációs tesztelés több mint 20 opcióval
• Beépített DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injektálás és snippet végrehajtás
• Egyéni User-Agent emuláció
• Viewport és eszköz emuláció

SFSafariViewController tesztelés
• Natív Safari élmény tartalomblokkolókkal
• Reader Mode és reszponzív méretvezérlés
• Testreszabható sávszínek és gombstílusok

Fejlesztői eszközök
• Console: console.log rögzítés %c CSS stílus támogatással
• Network: Fetch/XHR kérések figyelése időadatokkal
• Storage: localStorage, sessionStorage, sütik megtekintése/szerkesztése
• Performance: Web Vitals (LCP, FID, CLS) és Navigation Timing
• Sources: DOM fa vizsgálat, stíluslapok, szkriptek
• Accessibility: axe-core alapú akadálymentességi audit

További funkciók
• Könyvjelzőkezelés a gyors URL-hozzáféréshez
• Reszponzív viewport méretezés (iPhone, iPad, Desktop előbeállítások)
• Képernyőkép rögzítés
• API képesség észlelése
• Sötét mód támogatás

Tökéletes iOS fejlesztőknek, akiknek webtartalom renderelést kell tesztelniük, JavaScript-et debugolniuk, hálózati kéréseket elemezniük és akadálymentességi megfelelőséget biztosítaniuk.
""",
        "keywords": "webview,fejlesztő,debug,konzol,hálózat,safari,devtools,teszt,vizsgálat,ios,javascript,html,css",
        "promotionalText": "Új: a Mac Agenttel a kódoló asszisztensed oldalakat tesztelhet a Walnutban a Macről. Console, Network és Sources a WebView hibakereséshez."
    },
    "ro": {
        "name": "Walnut: Webview Test & Depanare",
        "subtitle": "Depanare WebView cu agenți",
        "description": """Instrumentul suprem pentru dezvoltatori pentru testarea configurațiilor WKWebView și SFSafariViewController în timp real.

MAC AGENT (NOU)
• Permite unui agent de codare sau terminalului tău Mac să controleze WKWebView din Walnut pe iPhone
• Deschide pagini, atinge și tastează, rulează scripturi și citește jurnalele Console și Network
• Alege aprobările: cere de fiecare dată, permite acțiuni în pagină sau permite totul
• Asociază o singură dată prin Wi-Fi sau USB cu o confirmare din 6 cifre

CARACTERISTICI PRINCIPALE

Testare WKWebView
• Testare configurație în timp real cu peste 20 de opțiuni
• DevTools încorporate: Console, Network, Storage, Performance, Sources, Accessibility
• Injectare JavaScript și execuție de snippeturi
• Emulare User-Agent personalizat
• Emulare viewport și dispozitiv

Testare SFSafariViewController
• Experiență Safari nativă cu blocatoare de conținut
• Reader Mode și control dimensiune responsiv
• Culori bară și stiluri butoane personalizabile

Instrumente pentru dezvoltatori
• Console: Captură console.log cu suport pentru stilizare CSS %c
• Network: Monitorizare cereri fetch/XHR cu date de sincronizare
• Storage: Vizualizare/editare localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) și Navigation Timing
• Sources: Inspecție arbore DOM, foi de stil, scripturi
• Accessibility: Audit de accesibilitate bazat pe axe-core

Caracteristici suplimentare
• Gestionare marcaje pentru acces rapid la URL-uri
• Redimensionare viewport responsiv (presetări iPhone, iPad, Desktop)
• Captură de ecran
• Detectare capabilități API
• Suport mod întunecat

Perfect pentru dezvoltatorii iOS care trebuie să testeze redarea conținutului web, să depaneze JavaScript, să analizeze cererile de rețea și să asigure conformitatea cu accesibilitatea.
""",
        "keywords": "webview,dezvoltator,debug,consolă,rețea,safari,devtools,test,inspector,ios,javascript,html,css",
        "promotionalText": "Nou: Mac Agent permite agentului tău de codare să testeze pagini în Walnut de pe Mac. Plus Console, Network și Sources integrate pentru depanarea WebView."
    },
    "hr": {
        "name": "Walnut: Webview Test & Debug",
        "subtitle": "Otklanjanje WebView s agentom",
        "description": """Ultimativni alat za programere za testiranje WKWebView i SFSafariViewController konfiguracija u stvarnom vremenu.

MAC AGENT (NOVO)
• Dopustite agentu za kodiranje ili Mac terminalu da upravlja WKWebView u Walnut na vašem iPhone
• Otvarajte stranice, dodirujte i tipkajte, pokrećite skripte i čitajte zapisnike Console i Network
• Odaberite odobrenja: pitaj svaki put, dopusti radnje na stranici ili dopusti sve
• Uparite jednom preko Wi-Fi ili USB uz 6-znamenkastu potvrdu

GLAVNE ZNAČAJKE

WKWebView testiranje
• Testiranje konfiguracije u stvarnom vremenu s više od 20 opcija
• Ugrađeni DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• JavaScript injekcija i izvršavanje isječaka
• Prilagođena User-Agent emulacija
• Emulacija viewporta i uređaja

SFSafariViewController testiranje
• Izvorno Safari iskustvo s blokatorima sadržaja
• Reader Mode i responzivna kontrola veličine
• Prilagodljive boje trake i stilovi gumba

Alati za programere
• Console: Hvatanje console.log s podrškom za %c CSS stiliziranje
• Network: Praćenje fetch/XHR zahtjeva s vremenskim podacima
• Storage: Pregled/uređivanje localStorage, sessionStorage, kolačića
• Performance: Web Vitals (LCP, FID, CLS) i Navigation Timing
• Sources: Inspekcija DOM stabla, stilske liste, skripte
• Accessibility: Revizija pristupačnosti temeljena na axe-core

Dodatne značajke
• Upravljanje oznakama za brzi pristup URL-ovima
• Responzivna promjena veličine viewporta (iPhone, iPad, Desktop predlošci)
• Hvatanje snimke zaslona
• Otkrivanje mogućnosti API-ja
• Podrška za tamni način

Savršeno za iOS programere koji trebaju testirati prikazivanje web sadržaja, debugirati JavaScript, analizirati mrežne zahtjeve i osigurati usklađenost s pristupačnošću.
""",
        "keywords": "webview,programer,debug,konzola,mreža,safari,devtools,test,inspektor,ios,javascript,html,css",
        "promotionalText": "Novo: Mac Agent omogućuje agentu za kodiranje testiranje stranica u Walnut s Mac računala. Ugrađeni Console, Network i Sources za WebView."
    },
    "el": {
        "name": "Walnut: Webview Δοκιμή & Debug",
        "subtitle": "Αποσφαλμάτωση WebView με agent",
        "description": """Το απόλυτο εργαλείο προγραμματιστή για δοκιμή διαμορφώσεων WKWebView και SFSafariViewController σε πραγματικό χρόνο.

MAC AGENT (ΝΕΟ)
• Επιτρέψτε σε έναν agent κώδικα ή στο τερματικό του Mac σας να χειρίζεται το WKWebView του Walnut στο iPhone σας
• Ανοίξτε σελίδες, πατήστε και πληκτρολογήστε, εκτελέστε scripts και διαβάστε καταγραφές Console και Network
• Επιλέξτε εγκρίσεις: ερώτηση κάθε φορά, άδεια για ενέργειες σελίδας ή άδεια για όλα
• Κάντε σύζευξη μία φορά μέσω Wi-Fi ή USB με επιβεβαίωση 6 ψηφίων

ΚΥΡΙΑ ΧΑΡΑΚΤΗΡΙΣΤΙΚΑ

Δοκιμή WKWebView
• Δοκιμή διαμόρφωσης σε πραγματικό χρόνο με πάνω από 20 επιλογές
• Ενσωματωμένα DevTools: Console, Network, Storage, Performance, Sources, Accessibility
• Έγχυση JavaScript και εκτέλεση snippets
• Προσαρμοσμένη εξομοίωση User-Agent
• Εξομοίωση viewport και συσκευής

Δοκιμή SFSafariViewController
• Εγγενής εμπειρία Safari με αποκλεισμό περιεχομένου
• Reader Mode και αποκριτικός έλεγχος μεγέθους
• Προσαρμόσιμα χρώματα γραμμής και στυλ κουμπιών

Εργαλεία προγραμματιστή
• Console: Σύλληψη console.log με υποστήριξη %c CSS styling
• Network: Παρακολούθηση αιτημάτων fetch/XHR με δεδομένα χρονισμού
• Storage: Προβολή/επεξεργασία localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) και Navigation Timing
• Sources: Επιθεώρηση δέντρου DOM, stylesheets, scripts
• Accessibility: Έλεγχος προσβασιμότητας βασισμένος στο axe-core

Επιπλέον χαρακτηριστικά
• Διαχείριση σελιδοδεικτών για γρήγορη πρόσβαση URL
• Αποκρινόμενη αλλαγή μεγέθους viewport (προεπιλογές iPhone, iPad, Desktop)
• Λήψη στιγμιότυπου οθόνης
• Ανίχνευση δυνατοτήτων API
• Υποστήριξη σκοτεινής λειτουργίας

Ιδανικό για iOS προγραμματιστές που χρειάζεται να δοκιμάσουν απόδοση περιεχομένου web, να κάνουν debug σε JavaScript, να αναλύσουν αιτήματα δικτύου και να εξασφαλίσουν συμμόρφωση προσβασιμότητας.
""",
        "keywords": "webview,προγραμματιστής,debug,κονσόλα,δίκτυο,safari,devtools,δοκιμή,ios,javascript,html,css",
        "promotionalText": "Νέο: Το Mac Agent δοκιμάζει σελίδες στο Walnut από το Mac μέσω agent κώδικα. Με Console, Network και Sources για WebView debugging."
    },
    "he": {
        "name": "Walnut: Webview בדיקה ודיבוג",
        "subtitle": "דיבוג WebView עם סוכן",
        "description": """הכלי האולטימטיבי למפתחים לבדיקת הגדרות WKWebView ו-SFSafariViewController בזמן אמת.

MAC AGENT (חדש)
• תנו לסוכן קידוד או למסוף ה-Mac שלכם לשלוט ב-WKWebView של Walnut ב-iPhone
• פתחו דפים, הקישו והקלידו, הריצו סקריפטים וקראו יומני Console ו-Network
• בחרו אישורים: לשאול בכל פעם, לאפשר פעולות בדף, או לאפשר הכול
• בצעו צימוד פעם אחת דרך Wi-Fi או USB עם אישור בן 6 ספרות

תכונות עיקריות

בדיקת WKWebView
• בדיקת הגדרות בזמן אמת עם יותר מ-20 אפשרויות
• DevTools מובנים: Console, Network, Storage, Performance, Sources, Accessibility
• הזרקת JavaScript והרצת snippets
• אמולציית User-Agent מותאמת אישית
• אמולציית viewport ומכשיר

בדיקת SFSafariViewController
• חוויית Safari מקורית עם חוסמי תוכן
• Reader Mode ובקרת גודל רספונסיבית
• צבעי סרגל וסגנונות כפתורים הניתנים להתאמה

כלי מפתחים
• Console: לכידת console.log עם תמיכה בעיצוב CSS %c
• Network: מעקב אחר בקשות fetch/XHR עם נתוני תזמון
• Storage: צפייה/עריכת localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) ו-Navigation Timing
• Sources: בדיקת עץ DOM, גיליונות סגנון, סקריפטים
• Accessibility: ביקורת נגישות מבוססת axe-core

תכונות נוספות
• ניהול סימניות לגישה מהירה לכתובות URL
• שינוי גודל viewport רספונסיבי (הגדרות iPhone, iPad, Desktop)
• צילום מסך
• זיהוי יכולות API
• תמיכה במצב כהה

מושלם למפתחי iOS שצריכים לבדוק רינדור תוכן אינטרנט, לדבג JavaScript, לנתח בקשות רשת ולהבטיח עמידה בדרישות נגישות.
""",
        "keywords": "webview,מפתח,דיבאג,קונסול,רשת,safari,devtools,בדיקה,בדיקת,ios,javascript,html,css,דפדפן,כלי,פיתוח",
        "promotionalText": "חדש: Mac Agent מאפשר לסוכן הקידוד לבדוק דפים ב-Walnut מה-Mac. כולל Console, Network ו-Sources לניפוי WebView."
    },
    "ca": {
        "name": "Walnut: Webview Test & Depuració",
        "subtitle": "Depuració WebView amb agents",
        "description": """L'eina definitiva per a desenvolupadors per provar configuracions de WKWebView i SFSafariViewController en temps real.

MAC AGENT (NOU)
• Permet que un agent de codi o el terminal del teu Mac controli el WKWebView de Walnut al teu iPhone
• Obre pàgines, toca i escriu, executa scripts i llegeix els registres de Console i Network
• Tria les aprovacions: pregunta sempre, permet accions a la pàgina o permet-ho tot
• Enllaça un cop per Wi-Fi o USB amb una confirmació de 6 dígits

CARACTERÍSTIQUES PRINCIPALS

Proves de WKWebView
• Proves de configuració en temps real amb més de 20 opcions
• DevTools integrades: Console, Network, Storage, Performance, Sources, Accessibility
• Injecció de JavaScript i execució de snippets
• Emulació de User-Agent personalitzat
• Emulació de viewport i dispositiu

Proves de SFSafariViewController
• Experiència Safari nativa amb blocadors de contingut
• Reader Mode i control de mida responsiu
• Colors de barra i estils de botó personalitzables

Eines de desenvolupador
• Console: Captura de console.log amb suport d'estil CSS %c
• Network: Monitoratge de peticions fetch/XHR amb dades de temps
• Storage: Veure/editar localStorage, sessionStorage, cookies
• Performance: Web Vitals (LCP, FID, CLS) i Navigation Timing
• Sources: Inspecció de l'arbre DOM, fulls d'estil, scripts
• Accessibility: Auditoria d'accessibilitat basada en axe-core

Característiques addicionals
• Gestió de marcadors per a accés ràpid a URLs
• Redimensionament de viewport responsiu (presets iPhone, iPad, Desktop)
• Captura de pantalla
• Detecció de capacitats d'API
• Suport de mode fosc

Perfecte per a desenvolupadors iOS que necessiten provar el renderitzat de contingut web, depurar JavaScript, analitzar peticions de xarxa i assegurar el compliment d'accessibilitat.
""",
        "keywords": "webview,desenvolupador,debug,consola,xarxa,safari,devtools,prova,inspector,ios,javascript,html,css",
        "promotionalText": "Nou: Mac Agent permet al teu agent de codi provar pàgines a Walnut des del Mac. Amb Console, Network i Sources integrats per depurar WebView."
    }
}

# Default fallback for missing languages (use English)
DEFAULT_LOCALE = "en-US"


def generate_jwt_token():
    """Generate JWT token for App Store Connect API authentication"""
    with open(PRIVATE_KEY_PATH, 'r') as key_file:
        private_key = key_file.read()

    now = int(time.time())
    payload = {
        "iss": ISSUER_ID,
        "iat": now,
        "exp": now + 1200,  # 20 minutes
        "aud": "appstoreconnect-v1"
    }

    headers = {
        "alg": "ES256",
        "kid": KEY_ID,
        "typ": "JWT"
    }

    token = jwt.encode(payload, private_key, algorithm="ES256", headers=headers)
    return token


def get_headers():
    """Get authorization headers for API requests"""
    token = generate_jwt_token()
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }


def get_app_id(bundle_id="com.kobbokkom.wina"):
    """Get App ID from bundle ID"""
    headers = get_headers()
    response = session.get(
        f"{BASE_URL}/apps",
        headers=headers,
        params={"filter[bundleId]": bundle_id}
    )
    response.raise_for_status()
    data = response.json()
    if data["data"]:
        return data["data"][0]["id"]
    raise ValueError(f"App with bundle ID {bundle_id} not found")


def get_app_info(app_id):
    """Get app info for the app - prefer editable state"""
    headers = get_headers()
    response = session.get(
        f"{BASE_URL}/apps/{app_id}/appInfos",
        headers=headers
    )
    response.raise_for_status()
    data = response.json()
    if data["data"]:
        # Prefer editable app info (not released)
        for info in data["data"]:
            state = info["attributes"].get("appStoreState", "")
            if state in ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "DEVELOPER_REJECTED", "REJECTED"]:
                print(f"   Using editable App Info (state: {state})")
                return info["id"]
        # Fall back to first if none are editable
        return data["data"][0]["id"]
    raise ValueError("No app info found")


def get_app_store_version(app_id):
    """Get the latest app store version"""
    headers = get_headers()
    # Get all versions without filter, then pick the editable one
    response = session.get(
        f"{BASE_URL}/apps/{app_id}/appStoreVersions",
        headers=headers
    )
    response.raise_for_status()
    data = response.json()
    if data["data"]:
        # Prefer versions that are editable (not released)
        for version in data["data"]:
            state = version["attributes"].get("appStoreState", "")
            if state in ["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "DEVELOPER_REJECTED", "REJECTED"]:
                return version["id"]
        # Fall back to first version if none are editable
        return data["data"][0]["id"]
    raise ValueError("No app store version found")


def get_existing_localizations(app_info_id):
    """Get existing app info localizations"""
    headers = get_headers()
    response = session.get(
        f"{BASE_URL}/appInfos/{app_info_id}/appInfoLocalizations",
        headers=headers
    )
    response.raise_for_status()
    data = response.json()
    return {item["attributes"]["locale"]: item["id"] for item in data["data"]}


def get_existing_version_localizations(version_id):
    """Get existing app store version localizations"""
    headers = get_headers()
    response = session.get(
        f"{BASE_URL}/appStoreVersions/{version_id}/appStoreVersionLocalizations",
        headers=headers
    )
    response.raise_for_status()
    data = response.json()
    return {item["attributes"]["locale"]: item["id"] for item in data["data"]}


def get_metadata_for_locale(locale):
    """Get metadata for a specific locale, falling back to English if needed"""
    if locale in METADATA:
        return METADATA[locale]

    # Map locales to their base language
    locale_mapping = {
        "en-AU": "en-US",
        "en-CA": "en-US",
        "en-GB": "en-US",
        "es-MX": "es-ES",
        "fr-CA": "fr-FR",
        "pt-PT": "pt-BR",
    }

    mapped_locale = locale_mapping.get(locale)
    if mapped_locale and mapped_locale in METADATA:
        return METADATA[mapped_locale]

    return METADATA[DEFAULT_LOCALE]


def update_app_info_localization(localization_id, locale, metadata):
    """No-op: app info updates are intentionally disabled."""
    return True


def create_app_info_localization(app_info_id, locale, metadata):
    """No-op: app info updates are intentionally disabled."""
    return True


def release_notes(locale):
    """Release notes live in fastlane/metadata/<locale>/release_notes.txt (one owner)."""
    path = Path(__file__).resolve().parent.parent / "fastlane" / "metadata" / locale / "release_notes.txt"
    return path.read_text().strip() if path.exists() else ""


def update_version_localization(localization_id, locale, metadata):
    """Update existing app store version localization"""
    headers = get_headers()
    payload = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": localization_id,
            "attributes": {
                "description": metadata.get("description", ""),
                "keywords": metadata.get("keywords", "")[:100],
                "whatsNew": release_notes(locale),
                "promotionalText": metadata.get("promotionalText", "")
            }
        }
    }

    response = session.patch(
        f"{BASE_URL}/appStoreVersionLocalizations/{localization_id}",
        headers=headers,
        json=payload
    )

    if response.status_code == 200:
        print(f"  ✅ Updated version info for {locale}")
        return True
    else:
        print(f"  ❌ Failed to update version info for {locale}: {response.status_code}")
        print(f"     {response.text[:200]}")
        return False


def create_version_localization(version_id, locale, metadata):
    """Create new app store version localization"""
    headers = get_headers()
    payload = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {
                "locale": locale,
                "description": metadata.get("description", ""),
                "keywords": metadata.get("keywords", "")[:100],
                "whatsNew": release_notes(locale),
                "promotionalText": metadata.get("promotionalText", "")
            },
            "relationships": {
                "appStoreVersion": {
                    "data": {
                        "type": "appStoreVersions",
                        "id": version_id
                    }
                }
            }
        }
    }

    response = session.post(
        f"{BASE_URL}/appStoreVersionLocalizations",
        headers=headers,
        json=payload
    )

    if response.status_code == 201:
        print(f"  ✅ Created version info for {locale}")
        return True
    else:
        print(f"  ❌ Failed to create version info for {locale}: {response.status_code}")
        print(f"     {response.text[:200]}")
        return False


def main():
    print("🚀 Starting App Store metadata upload...")
    print()

    # Get app info
    print("📱 Getting app information...")
    app_id = get_app_id()
    print(f"   App ID: {app_id}")

    app_info_id = get_app_info(app_id)
    print(f"   App Info ID: {app_info_id}")

    version_id = get_app_store_version(app_id)
    print(f"   Version ID: {version_id}")
    print()

    # Get existing localizations
    print("📋 Getting existing localizations...")
    existing_app_info = get_existing_localizations(app_info_id)
    existing_version = get_existing_version_localizations(version_id)
    print(f"   Existing app info locales: {len(existing_app_info)}")
    print(f"   Existing version locales: {len(existing_version)}")
    print()

    # Process each locale
    print("🌍 Processing localizations...")
    success_count = 0
    fail_count = 0

    for locale in LOCALES:
        print(f"\n📝 Processing {locale}...")
        metadata = get_metadata_for_locale(locale)

        # Update or create app info localization
        if locale in existing_app_info:
            if update_app_info_localization(existing_app_info[locale], locale, metadata):
                success_count += 1
            else:
                fail_count += 1
        else:
            if create_app_info_localization(app_info_id, locale, metadata):
                success_count += 1
            else:
                fail_count += 1

        # Update or create version localization
        if locale in existing_version:
            if update_version_localization(existing_version[locale], locale, metadata):
                success_count += 1
            else:
                fail_count += 1
        else:
            if create_version_localization(version_id, locale, metadata):
                success_count += 1
            else:
                fail_count += 1

    print()
    print("=" * 50)
    print(f"✅ Complete! Success: {success_count}, Failed: {fail_count}")
    print(f"🌍 Processed {len(LOCALES)} locales")


if __name__ == "__main__":
    main()
