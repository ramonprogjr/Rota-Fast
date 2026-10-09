# Rota Food

Planejador de rotas para entregadores de comida (pizzaria, restaurante, dark kitchen).

Versão 1.1 — Android, gratuito, sem anúncios e sem assinatura.

O Rota Food organiza várias entregas do turno. Você confirma o ponto no mapa; o **Navegar** abre o Google Maps com o **texto do endereço**. Dá para fotografar comandas (OCR no celular), iniciar o turno para registrar km e ver o relatório do dia (gasolina e óleo a cada 1000 km).

## O que o app faz

- Cadastra pedidos com cliente, endereço, telefone, valor e prioridade
- Cola vários endereços de uma vez (incluindo texto do WhatsApp)
- Fotografa até 5 comandas; o OCR lê o texto no celular (nada sobe para a nuvem)
- Busca até 5 candidatos no OpenStreetMap e pede confirmação no mapa (dá para ajustar o pino)
- Sugere uma sequência com o algoritmo do vizinho mais próximo
- Mostra distância e tempo estimados (linha reta, velocidade média de moto)
- Abre o Google Maps com o **texto do endereço** (não com a coordenada do OSM)
- Marca como entregue e recalcula o restante da rota
- Inicia o turno no GPS, mostra o mapa do dia, km, gasolina estimada e óleo a cada 1000 km
- Envia o relatório do dia no WhatsApp; histórico fica só no celular

## O que o app não faz

Não substitui o Google Maps. Distâncias no app são estimativas em linha reta. Ruas, trânsito e bloqueios ficam a cargo do Maps.

## Segurança no trânsito

Configure a rota com o celular parado. Use suporte no guidão e os comandos de voz do Google Maps. Não mexa no aplicativo em movimento.

## Como gerar o APK

É preciso ter [Flutter](https://docs.flutter.dev/get-started/install) e o Android SDK.

Para o Supabase da fase de plataforma, os valores podem entrar em tempo de build com `dart-define`:

```bash
flutter run \
	--dart-define=SUPABASE_URL=https://SEU_PROJETO.supabase.co \
	--dart-define=SUPABASE_ANON_KEY=SEU_ANON_KEY
```

Se a configuração não estiver presente, o app continua funcionando em modo local/offline com o SQLite.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

O arquivo sai em:

`build/app/outputs/flutter-apk/app-release.apk`

Uma cópia conveniente pode ficar em `dist/rota-food.apk` ou `dist/rota-pizza.apk` (essa pasta não vai para o Git). O `applicationId` continua `com.rotapizza.rota_pizza` para o APK atualizar o app já instalado.

Se a pasta do projeto tiver acento (`Área de Trabalho`), o build de release no Windows pode falhar no snapshot AOT. Gere o APK a partir de um caminho só com ASCII, por exemplo `C:\Users\ramon\rota-pizza-build`. O Gradle já tem `android.overridePathCheck=true`.

## Geocodificação (Nominatim)

O app consulta `nominatim.openstreetmap.org` (até 5 candidatos, User-Agent `RotaFood/1.1`) com no máximo cerca de 1 pedido por segundo. O ponto só entra no cache depois que você confirma no mapa.

- Cidade padrão: São Bernardo do Campo
- Sem chave de API
- Sem internet, você ainda vê, edita e conclui entregas já salvas
- Endereços novos só são localizados com rede

Se o pino cair no lugar errado, escolha outro candidato ou arraste o marcador. O **Navegar** usa o endereço escrito, não a lat/lng do OSM.

Fora desta versão (ideia para depois): foto da fachada em endereço difícil; OCR ainda melhor com chave Google Cloud.

## Estrutura

```
lib/
	core/          tema, constantes, parser, distância
	models/
	data/          SQLite e repositórios
	services/      Nominatim, rota, Maps, GPS
	providers/
	screens/
	widgets/
test/
docs/
```

## Licença

MIT. Dados dos clientes ficam só no aparelho; não há conta nem servidor próprio.
