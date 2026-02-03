# Добавление SPM зависимостей

Проект открыт в Xcode! Теперь добавь SPM пакеты:

## 1. Socket.io для WebSocket

File → Add Package Dependencies → вставь URL:
```
https://github.com/socketio/socket.io-client-swift
```
Version: 16.1.0 или выше
Target: RecipeScalerNative

## 2. KeychainAccess для хранения

```
https://github.com/kishikawakatsumi/KeychainAccess
```
Version: 4.2.2 или выше
Target: RecipeScalerNative

## 3. BIP39 для seed phrase

```
https://github.com/anquii/BIP39
```
Version: 1.0.0 или выше
Target: RecipeScalerNative

## После добавления

1. Build проект (Cmd+B)
2. Если ошибки импортов - проверь что пакеты добавлены в Target
3. Настрой baseURL в `APIClient.swift`
4. Run (Cmd+R)

## Настройка Team ID

Project Settings → Signing & Capabilities → Team:
- Выбери свой Apple Developer Team
- Или используй "Personal Team" для локальной разработки

Готово! 🚀
