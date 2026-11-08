# Instalar o APK no celular (teste sem Play Store)

1. No computador, com Flutter no PATH. Se a pasta do projeto tiver acento (como `Área de Trabalho`), o build de release no Windows pode falhar. Nesse caso, copie o projeto para um caminho só com ASCII e gere o APK de lá.

```bash
flutter pub get
flutter test
flutter build apk --release
```

2. O arquivo gerado fica em `build/app/outputs/flutter-apk/app-release.apk`.

3. Copie o APK para o celular (cabo, Drive, WhatsApp para você mesmo).

4. No Android: Configurações → Segurança → permitir instalar apps desta fonte.

5. Abra o APK e instale.

6. Na primeira abertura:
   - Cadastre o ponto de saída (endereço + Localizar / Salvar)
   - Adicione, cole ou fotografe as entregas
   - Toque em Organizar rota (com o celular parado)
   - Use Navegar para abrir o Google Maps ou o Waze

7. Permissões: localização (origem da rota e km do turno) e câmera (etiquetas). Internet só é necessária para achar endereços novos, carregar o mapa e navegar.

Sem o arquivo `android/key.properties`, o APK sai assinado com a chave de debug: serve para teste, não para a Play Store. Para publicar, ver [play-store.md](play-store.md).

O Rota Max (`com.rotamax.app`) é um app diferente do antigo Rota Food (`com.rotapizza.rota_pizza`): os dois podem ficar instalados juntos e os dados não são migrados.
