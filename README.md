# Rota Max

**Sua rota. Seu controle. Seu resultado.**

Planejador e gerenciador de rotas de entrega para entregadores autônomos, motoristas parceiros e pequenas operações. Android, Flutter, **offline-first**: os dados ficam no celular (SQLite), sem conta e sem servidor.

## O que o app faz

- Cadastra entregas à mão, colando vários endereços (inclusive texto do WhatsApp) ou fotografando até 5 etiquetas/comandas (OCR no próprio celular)
- Localiza os endereços no OpenStreetMap e pede confirmação no mapa
- Organiza a sequência (vizinho mais próximo + 2-opt, respeitando prioridade)
- Abre a próxima parada no Google Maps ou no Waze
- Marca entregue, não entregue (com motivo) ou pulada, e recalcula o resto da rota
- Registra o turno pelo GPS: km, combustível, troca de óleo e relatório do dia no WhatsApp

Distâncias e tempos no app são **estimativas**. Ruas, trânsito e bloqueios ficam com o app de navegação.

## Segurança no trânsito

Configure a rota com o celular parado. Use suporte no guidão e os comandos de voz do app de navegação.

## Desenvolvimento

Requer [Flutter](https://docs.flutter.dev/get-started/install) (stable) e Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Build para a Play Store (precisa de `android/key.properties`, ver [docs/play-store.md](docs/play-store.md)):

```bash
flutter build appbundle --release
```

APK para instalar direto no celular: [docs/install.md](docs/install.md).

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Documento mestre do produto |
| [docs/AUDIT.md](docs/AUDIT.md) | Auditoria do código herdado do Rota Food |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Camadas, pastas e integrações |
| [docs/DATABASE.md](docs/DATABASE.md) | Schema SQLite, migrations e máquina de estados |
| [docs/BACKLOG.md](docs/BACKLOG.md) | O que está pronto e o que falta, por etapa |

## Geocodificação (Nominatim)

Consulta `nominatim.openstreetmap.org` com no máximo 1 pedido por segundo e User-Agent identificado. O ponto só entra no cache depois de confirmado no mapa, e o cache é consultado antes da rede. Sem internet, entregas já localizadas continuam funcionando; endereços novos ficam aguardando localização.

## Licença

MIT. Dados dos clientes ficam só no aparelho.
