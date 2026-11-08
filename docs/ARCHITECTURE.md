# Arquitetura — Rota Max v1

App Android em Flutter, **offline-first**, para um entregador individual. Não há servidor próprio: os dados ficam no SQLite do aparelho. A internet é usada só para geocodificar endereços novos (Nominatim), baixar os blocos do mapa (OpenStreetMap) e abrir a navegação (Google Maps / Waze).

```text
Telas (lib/screens, lib/widgets)
        │  context.watch / read
        v
AppState (lib/providers/app_state.dart) — ChangeNotifier (Provider)
        │
        ├── Repositories (lib/data/repositories) ── SQLite (lib/data/database.dart)
        │      entregas, rota, eventos, turno, configurações, ponto de saída, cache
        │
        └── Services (lib/services)
               route_optimizer   vizinho mais próximo + 2-opt
               geocoding_service Nominatim + cache
               ocr_service       ML Kit no aparelho
               location_service  GPS pontual
               shift_tracker     GPS contínuo do turno (foreground service)
               maps_service      Google Maps / Waze
```

## Regras de camada

- **Telas** não falam com o banco nem com serviços externos: chamam métodos do `AppState`.
- **AppState** orquestra: decide o que fazer e chama repositórios e serviços. Mantém em memória a lista atual para a interface.
- **Repositories** são a única porta para o SQLite. Cada um tem uma interface abstrata e duas implementações: SQLite (app) e memória (testes).
- **Services** não guardam estado de tela. Funções puras sempre que possível (`route_optimizer`, `address_parser`, `haversine`, `maintenance`) para serem testadas sem Flutter.
- Toda troca de status de entrega passa por um único método transacional do repositório, que também grava o evento (ver [DATABASE.md](DATABASE.md)).

## Pastas

```text
lib/
  core/        constantes, tema, utilitários puros (parser, distância, manutenção)
  models/      classes de dados imutáveis com toMap/fromMap
  data/        database.dart (schema + migrations) e repositories/
  services/    integrações e algoritmos
  providers/   AppState
  screens/     uma tela por arquivo
  widgets/     componentes reutilizáveis
test/          unitários e de widget; helpers/ monta AppState em memória
docs/          PRD, auditoria, arquitetura, banco, backlog
```

A estrutura por `features/` sugerida no PRD §9.2 **não** foi adotada agora: o PRD pede para preservar a organização existente, e a troca não traz ganho com o tamanho atual do app.

## Integrações externas

| Serviço | Uso | Offline |
|---|---|---|
| Nominatim (OSM) | Endereço → coordenadas, até 5 candidatos, 1 req/s, cache local | Usa o cache; endereço novo fica sem coordenada até ter rede |
| Tiles OSM | Fundo do mapa | Mapa sem fundo; marcadores continuam |
| Google ML Kit | OCR de etiquetas, no aparelho | Funciona |
| Google Maps / Waze | Navegação turn-by-turn por intent | Depende do app de navegação |
| WhatsApp | Envio do relatório e contato com o cliente | — |

## Fase futura (fora da v1)

Login, empresas, equipes e sincronização em nuvem. O esboço do banco Postgres/Supabase está em `supabase/` como referência; nenhum código do app depende dele.
