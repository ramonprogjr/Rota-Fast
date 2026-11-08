# Banco de dados — Rota Max v1

SQLite local, arquivo `rota_max.db`, via `sqflite`. Definido em `lib/data/database.dart`.

## Regras

1. **Toda mudança de estrutura é uma migration nova.** Nunca editar uma migration já publicada.
2. Migrations ficam numa lista ordenada (`_migrations`). A versão do banco é o tamanho da lista. `onCreate` roda todas; `onUpgrade` roda de `oldVersion + 1` até a atual. Cada migration roda dentro de uma transação.
3. `PRAGMA foreign_keys = ON` em todo `open` (`onConfigure`).
4. Operações críticas (troca de status + evento, gravar ordem da rota) rodam em transação.
5. Datas em texto ISO-8601 (horário local do aparelho).

## Schema (versão 1)

### deliveries
| Coluna | Tipo | Observação |
|---|---|---|
| id | INTEGER PK | |
| order_number | TEXT | número do pedido/comanda |
| package_id | TEXT | código do pacote/etiqueta |
| customer_name | TEXT NOT NULL | |
| phone | TEXT | |
| address | TEXT NOT NULL | logradouro (PRD: `street`) |
| number, complement, neighborhood | TEXT | |
| postal_code | TEXT | CEP, só dígitos |
| city | TEXT NOT NULL | |
| state | TEXT | UF |
| latitude, longitude | REAL | null = ainda não localizado |
| location_confirmed | INTEGER 0/1 | ponto conferido no mapa |
| value | REAL | valor do pedido |
| notes | TEXT | observações |
| priority | TEXT | `normal` / `high` / `urgent` |
| status | TEXT | `PENDING` / `IN_PROGRESS` / `DELIVERED` / `FAILED` / `SKIPPED` |
| failure_reason | TEXT | último motivo de insucesso |
| attempts | INTEGER | tentativas que terminaram em FAILED |
| created_at, updated_at | TEXT NOT NULL | |
| delivered_at | TEXT | |
| deleted_at | TEXT | exclusão lógica. Toda leitura do app ignora linhas com valor aqui |

### routes
Uma rota do dia. Só uma pode estar `active` por vez.
`id`, `name` (opcional; sem nome a tela usa a data), `status` (`draft`/`active`/`completed`), `started_at`, `completed_at`, `origin_lat`, `origin_lng`, `end_lat`, `end_lng` (ponto final opcional), `manually_edited` (0/1), `estimated_km`, `estimated_minutes`, `nav_app`, `created_at`.

`manually_edited = 1` quando o motorista muda a ordem na mão ("Editar ordem"). Enquanto estiver em 1, a rota **não** é reorganizada sozinha depois de cada entrega/não entrega (só a próxima parada avança). Volta a 0 quando a ordem é recalculada ("Organizar rota" / "Recalcular respeitando travas").

### route_stops
Ordem das paradas de uma rota. `route_id` → routes (CASCADE), `delivery_id` → deliveries (CASCADE), `position`, `locked` (0/1), `fixed_position` (null ou índice 0-based entre as paradas abertas). Único por `(route_id, delivery_id)`.

- `locked = 1` (cadeado): ao recalcular, a parada fica no índice em que está.
- `fixed_position = n` (alfinete): ao recalcular, a parada vai para o índice `n` (limitado ao tamanho da lista). Vale mais que `locked`.
- Gravar uma nova ordem preserva `locked`/`fixed_position` das paradas que continuam, e paradas abertas que não vierem na nova ordem vão para o fim (nunca perdem a posição).

### delivery_events
Histórico da entrega. `delivery_id` → deliveries (CASCADE), `kind` (`status`/`edit`, padrão `status`), `from_status`, `to_status`, `reason`, `note`, `latitude`, `longitude`, `changed_fields`, `created_at`.

- `kind = 'status'`: troca de status (`from_status` → `to_status`).
- `kind = 'edit'`: edição de dados; `from_status = to_status` = status atual e `changed_fields` lista as colunas alteradas separadas por vírgula (ex.: `customer_name,number`). A exclusão é registrada como `edit` com `changed_fields = 'deleted_at'`.

### route_plans
Economia de cada "Organizar rota" feito pelo motorista. `route_id` → routes (CASCADE), `stops`, `baseline_km`/`baseline_minutes` (paradas na ordem em que foram cadastradas), `optimized_km`/`optimized_minutes`. O relatório usa, por rota, o plano com mais paradas, para não contar a mesma rota duas vezes.

### vehicles
Veículos do motorista. Só um com `is_active = 1` (índice único parcial).
`name`, `type` (`motorcycle`/`car`/`utility`/`van`/`truck`), `plate`, `fuel_type` (`gasoline`/`ethanol`/`flex`/`diesel`), `km_per_liter`, `fuel_price`, `avg_speed_kmh` (usada no ETA), `odometer_km`, `oil_interval_km`, `last_oil_change_km`, `is_active`, `created_at`.

### oil_changes
Histórico de trocas de óleo. `vehicle_id` → vehicles (CASCADE), `odometer_km`, `changed_at`, `note`.

### error_log
Últimos erros do app (no máximo 50; os mais antigos saem a cada gravação). Só `source` (onde foi pego: `flutter`, `platform`, `zone`, nome da ação), `error_type` (tipo da exceção) e `location` (primeiro `package:rota_max/...:linha` da pilha), `created_at`. **Nunca grava a mensagem do erro**, que pode conter nome ou endereço de cliente. Ajustes mostra a contagem.

### Demais tabelas
- `base_location`: ponto de saída. Uma linha, id = 1, com nome, endereço, cidade e lat/lng.
- `settings`: chave/valor, por exemplo o app de navegação preferido.
- `geocode_cache`: consulta normalizada → coordenada confirmada.
- `shifts`: turnos de GPS. `vehicle_id` → vehicles (SET NULL). `track_points` → shifts (CASCADE).

### Índices
`deliveries(status, created_at)`, `route_stops(route_id, position)`, `route_stops(delivery_id)`, `delivery_events(delivery_id, created_at)`, `track_points(shift_id)`, `routes(status)`, `route_plans(route_id)`, `oil_changes(vehicle_id, changed_at)` e o único parcial `vehicles(is_active) WHERE is_active = 1`.

> Enquanto a v1 não for publicada, o schema fica todo na migration 1. Depois da primeira publicação, qualquer mudança vira migration nova.

## Exclusão

- **Entrega**: exclusão lógica (`deleted_at`). Sai da rota ativa, some de todas as leituras e o histórico de eventos fica, com um evento `edit` de exclusão.
- **Rota**: `DELETE` em `routes`; `route_stops` e `route_plans` saem junto (CASCADE). As entregas nunca são apagadas: as abertas só deixam de ter posição e voltam para a lista.
- **Reabrir rota**: a rota ativa atual é concluída e a escolhida volta a `active` (`completed_at = NULL`).

## Máquina de estados (PRD §13.1)

```text
PENDING ──> IN_PROGRESS ──> DELIVERED
   │             │  └─────> FAILED ──┐
   │             └────────> SKIPPED ─┤
   ├──> DELIVERED / FAILED / SKIPPED │  (marcar direto da lista)
   └<────────────────────────────────┘  "Tentar de novo"
DELIVERED ──> PENDING  só pela ação explícita "Reabrir"
IN_PROGRESS ──> PENDING  ao trocar de próxima parada
```

Toda transição grava uma linha em `delivery_events` na mesma transação. Transições fora deste desenho são recusadas pelo repositório.
