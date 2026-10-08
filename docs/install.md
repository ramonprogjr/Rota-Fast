# Instalar o APK no celular

1. No computador, com Flutter no PATH. Se a pasta do projeto tiver acento (como `Área de Trabalho`), o build de release no Windows pode falhar. Nesse caso, copie o projeto para um caminho só com ASCII, por exemplo `C:\Users\ramon\rota-pizza-build`, e gere o APK de lá.

```bash
flutter pub get
flutter test
flutter build apk --release
```

2. O arquivo gerado:

`build/app/outputs/flutter-apk/app-release.apk`

Neste workspace também há uma cópia em `dist/rota-pizza.apk`.

3. Copie o APK para o celular (cabo, Drive, WhatsApp para você mesmo).

4. No Android: Configurações → Segurança → permitir instalar apps desta fonte.

5. Abra o APK e instale.

6. Na primeira abertura:
   - Cadastre a pizzaria (endereço + Localizar / Salvar)
   - Adicione ou cole as entregas
   - Toque em Organizar rota (parado)
   - Use Navegar para abrir o Google Maps

7. Permissões: o app pode pedir localização para usar o GPS como origem. Internet é necessária só para achar endereços novos e abrir o Maps.

Este APK usa a assinatura de debug (definida no Gradle) para instalação direta, sem Play Store.
