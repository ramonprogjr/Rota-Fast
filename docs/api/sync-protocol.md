# Protocolo de sincronização — Rota Max v1

O app continua **offline-first**: o SQLite do aparelho é a fonte durante o turno. A API só recebe as mudanças (push) e devolve as dos outros aparelhos (pull). Sem login, nada disso roda e o app funciona igual.

- Endpoints: `POST /v1/sync/push` e `GET /v1/sync/pull` (contrato completo em [openapi.json](openapi.json)).
- Implementação: `apps/api/src/synchronization/` (regras), `apps/api/src/persistence/entity-writer.ts` (versão e log de mudanças).

## 1. Conceitos

| Conceito | Onde | Regra |
|---|---|---|
| **UUID de entidade** | gerado no aparelho | Toda linha sincronizável ganha um UUID v4 na criação. O servidor nunca troca o id. |
| **Operação** | fila local `sync_queue` | Cada mudança local vira `{operationId, entityType, entityId, operationType, payload, baseVersion, clientCreatedAt}` na **mesma transação SQLite** da mudança (outbox). |
| **operationId** | UUID v4 do aparelho | Chave de idempotência. Reenviar a mesma operação nunca aplica duas vezes. |
| **version** | coluna em toda entidade no servidor | Começa em 1 e sobe 1 a cada mudança. O app guarda a última versão que conhece. |
| **field_versions** | servidor | Mapa `campo → versão em que mudou por último`. Permite mesclar edições em campos diferentes. |
| **baseVersion** | operação | Versão que o aparelho conhecia quando editou. Obrigatória em `update`. |
| **cursor** | `settings.sync_cursor` | Posição no log de mudanças do servidor (`sync_changes.seq`, bigserial). Monotônico por usuário. |
| **tombstone** | pull | Entidade excluída (exclusão lógica): vem com `operation = "delete"` e `data = null`. |

### Entidades sincronizadas (`entityType`)

`delivery`, `route`, `route_stop`, `delivery_event`, `route_plan`, `vehicle`, `oil_change`, `shift`, `base_location`.

Não sincronizam: `settings`, `geocode_cache`, `error_log` (locais) e `track_points` (viram o resumo `shift.track`).

### Operações (`operationType`)

| Operação | Vale para | Payload | Observação |
|---|---|---|---|
| `create` | todas | retrato completo (camelCase) | Na criação pode vir `status`, `attempts`, `deliveredAt` (primeiro backup de entregas com histórico). |
| `update` | todas menos `delivery_event` e `route_plan` | **só os campos alterados** | `baseVersion` obrigatório. Em `delivery`, `status`/`failureReason`/`attempts`/`deliveredAt` são proibidos → use `transition`. |
| `delete` | todas menos `delivery_event` | `{}` | Exclusão lógica. `route` leva junto paradas e planos; `delivery` leva junto as paradas; `vehicle` leva as trocas de óleo. Entregas nunca são apagadas por excluir uma rota. `baseVersion` opcional: se vier e estiver velha, conflito. |
| `transition` | `delivery` | `{eventId, toStatus, fromStatus?, reason?, note?, latitude?, longitude?, occurredAt?}` | Mesma máquina de estados do app. Grava o `delivery_event` com `eventId`. |
| `reorder` | `route` | `{stopIds: [...]}` | Lista completa das paradas **abertas** da rota, na ordem nova. `baseVersion` opcional (compara com o "campo" `stopOrder`). |

## 2. Push

```http
POST /v1/sync/push
Authorization: Bearer <access_token do Supabase>

{
  "deviceId": "3f1c…",
  "operations": [
    { "operationId": "a1…", "entityType": "delivery", "entityId": "d1…", "operationType": "create",
      "payload": { "customerName": "Maria", "address": "Rua A", "number": "10", "city": "São Bernardo do Campo",
                   "latitude": -23.69, "longitude": -46.56, "createdAt": "2026-11-08T13:00:00Z" },
      "clientCreatedAt": "2026-11-08T13:00:00Z" },
    { "operationId": "a2…", "entityType": "delivery", "entityId": "d1…", "operationType": "transition",
      "payload": { "eventId": "e1…", "fromStatus": "PENDING", "toStatus": "DELIVERED",
                   "occurredAt": "2026-11-08T13:40:00Z" } }
  ]
}
```

Resposta (sempre 200 se o lote foi processado; erros por operação vêm no corpo):

```json
{
  "results": [
    { "operationId": "a1…", "entityType": "delivery", "entityId": "d1…", "status": "applied", "version": 1 },
    { "operationId": "a2…", "entityType": "delivery", "entityId": "d1…", "status": "applied", "version": 2 }
  ],
  "summary": { "applied": 2, "duplicate": 0, "conflict": 0, "rejected": 0 },
  "serverTime": "2026-11-08T13:41:02.120Z"
}
```

### Regras do servidor

1. Lote de 1 a **500** operações (mais que isso = 400). Rate limit do push: 30 lotes/minuto por cliente.
2. O lote roda **numa transação**, com `pg_advisory_xact_lock(usuário)`: dois lotes do mesmo usuário nunca se intercalam, e o `seq` do log é confirmado em ordem (o pull nunca pula mudança).
3. As operações são aplicadas **na ordem do array**. Crie pais antes de filhos (`route` e `delivery` antes de `route_stop`).
4. O aparelho é registrado automaticamente (`devices`) se ainda não existir. `deviceId` de outro usuário = 409 `DEVICE_ID_TAKEN`.
5. **Idempotência**: `operationId` já processado para o mesmo usuário → `status: "duplicate"`, com `originalStatus` e o resultado original (mesma `version`, mesmo `reason`). Nada é reaplicado. `operationId` de outro usuário → `rejected / operation_id_reused` (sem vazar nada).
6. **Dono**: toda entidade e toda referência (`routeId`, `deliveryId`, `vehicleId`) precisa ser do usuário do token. Senão `rejected / not_found` ou `reference_not_found` — o servidor não revela se o id existe para outra pessoa. `user_id` nunca vem do corpo.
7. Toda operação processada (applied, conflict, rejected) fica guardada em `sync_operations` com payload e resultado. **Nenhuma mudança é descartada em silêncio.**
8. Se uma operação causar um erro inesperado, o lote é refeito sem ela e ela volta como `rejected / internal_error` (até 3 vezes); se o banco estiver fora, o lote inteiro falha com 503 e nada é aplicado — reenvie depois (é idempotente).

### Resultados possíveis

| status | quando | o app faz |
|---|---|---|
| `applied` | aplicada. `version` = versão nova da entidade. `message: "already_in_status"` / `"already_deleted"` quando o servidor já estava no estado pedido (convergiu). | Marca a operação como enviada e grava `version` na linha local. |
| `duplicate` | `operationId` já processado. | Igual a `originalStatus`. |
| `conflict` | ver tabela abaixo. Vem `server` (retrato atual) e `version`. | Ver §4. |
| `rejected` | payload inválido, transição proibida, sem dono, etc. Vem `reason` e `details`. | Marca como recusada, não reenvia; mostra em Ajustes › Sincronização. `internal_error` pode ser reenviada com **outro** `operationId` mais tarde. |

### Motivos (`reason`)

| reason | status | significado |
|---|---|---|
| `version_conflict` | conflict | Algum campo do `update` mudou no servidor depois de `baseVersion` (`details.fields`). Campos diferentes são mesclados sem conflito. |
| `status_conflict` | conflict | `fromStatus` da transição ≠ status atual, e o destino também é diferente. |
| `deleted` | conflict | Update/transição em entidade já excluída. |
| `already_exists` | conflict | `create` com id que já existe (do mesmo usuário) com outro `operationId`. |
| `active_route_exists` / `active_vehicle_exists` | conflict | Só uma rota ativa e um veículo ativo por usuário. Mande antes a operação que conclui/desativa o outro. |
| `stop_exists` | conflict | A entrega já está viva nesta rota. |
| `stops_mismatch` | conflict | `reorder` com lista de abertas diferente da do servidor (`details.missing`, `details.unknown`). |
| `invalid_payload` | rejected | Falhou na validação (`details` = lista de problemas). Campos desconhecidos também. |
| `base_version_required`, `invalid_base_version` | rejected | `update` sem `baseVersion`, ou maior que a versão do servidor. |
| `use_transition` | rejected | `update` de entrega tentando mudar status. |
| `invalid_transition`, `failure_reason_required` | rejected | Fora da máquina de estados / FAILED sem motivo. |
| `invalid_route_transition` | rejected | draft→active/completed, active→completed/draft, completed→active. |
| `not_found`, `reference_not_found` | rejected | Entidade ou referência não existe para este usuário. |
| `immutable_entity`, `unsupported_operation`, `device_mismatch`, `operation_id_reused`, `internal_error` | rejected | — |

## 3. Pull

```http
GET /v1/sync/pull?since=<cursor>&limit=200
```

```json
{
  "changes": [
    { "seq": "1042", "entityType": "delivery", "entityId": "d1…", "operation": "upsert", "version": 2,
      "data": { "id": "d1…", "customerName": "Maria", "status": "DELIVERED", "version": 2, "…": "…" },
      "deletedAt": null },
    { "seq": "1047", "entityType": "route", "entityId": "r9…", "operation": "delete", "version": 5,
      "data": null, "deletedAt": "2026-11-08T14:00:00.000Z" }
  ],
  "nextCursor": "1047",
  "hasMore": false,
  "serverTime": "2026-11-08T14:00:03.000Z"
}
```

- `since` = último `nextCursor` salvo (`"0"` na primeira vez). `limit` 1–1000 (padrão 200).
- Só mudanças do usuário do token, em ordem de `seq`. Inclui as que o próprio aparelho enviou (o app ignora pela versão).
- `data` é o **retrato atual** (camelCase, sem `userId` nem `fieldVersions`). Dentro de uma página cada entidade aparece uma vez (a mudança mais nova); entre páginas pode reaparecer — aplicar sempre por versão.
- `hasMore = true` → chame de novo com `nextCursor`. Salve o cursor **depois** de aplicar a página, na mesma transação SQLite.

## 4. Conflitos — regras

1. **Edição × edição**: conflito só se os **mesmos campos** mudaram depois de `baseVersion`. Campos diferentes são mesclados (o servidor aplica só os do `update`).
2. **Status**: a transição só vale se `fromStatus` = status atual no servidor. Se o servidor já está no destino, converge (`applied`, sem evento novo). Senão `status_conflict` — o servidor mantém o dele.
3. **Exclusão × edição**: edição em entidade excluída = `deleted`. Exclusão com `baseVersion` velha = `version_conflict` (sem `baseVersion` a exclusão força).
4. **Ordem da rota**: `reorder` exige a mesma lista de abertas do servidor. Com `baseVersion`, outra reordenação depois dela = conflito.
5. O servidor **nunca** resolve sozinho apagando a mudança do aparelho: ela fica em `sync_operations` (status `conflict`) e volta para o app com o retrato do servidor.

**Política do app (v1)**: o servidor vence nos campos em conflito; o app aplica `server` na linha local, guarda a operação como `conflict` na `sync_queue` e mostra em Ajustes › Sincronização ("Alterado em outro aparelho"), com o botão **Usar a minha versão**, que cria uma operação nova (outro `operationId`) com `baseVersion = server.version`.

## 5. Diagramas

### Push e pull normais

```mermaid
sequenceDiagram
    autonumber
    participant UI as Tela
    participant DB as SQLite (app)
    participant Q as sync_queue
    participant API as API /v1
    participant PG as Postgres (Supabase)

    UI->>DB: marcar entrega como entregue
    DB->>DB: transação: UPDATE deliveries + INSERT delivery_events
    DB->>Q: (mesma transação) INSERT op transition (operationId novo)
    Note over Q: offline: fica na fila

    Q->>API: POST /sync/push {deviceId, operations[≤500]}
    API->>PG: BEGIN; advisory lock(usuário)
    loop cada operação, em ordem
        API->>PG: já existe sync_operations[operationId]?
        alt nova
            API->>PG: valida dono, versão, máquina de estados
            API->>PG: aplica (version+1) + INSERT sync_changes(seq)
            API->>PG: INSERT sync_operations(status, result)
        else repetida
            API-->>API: devolve resultado original (duplicate)
        end
    end
    API->>PG: COMMIT
    API-->>Q: results[] (applied/duplicate/conflict/rejected)
    Q->>DB: grava version nas linhas; tira da fila

    DB->>API: GET /sync/pull?since=cursor
    API->>PG: SELECT sync_changes WHERE user AND seq > cursor
    API-->>DB: changes[] + nextCursor + hasMore
    DB->>DB: transação: aplica por versão + salva cursor
```

### Conflito de edição

```mermaid
sequenceDiagram
    participant A as Aparelho A
    participant B as Aparelho B
    participant API as API

    Note over A,B: os dois têm a entrega na versão 1
    A->>API: update {number:"20"} baseVersion=1
    API-->>A: applied, version 2
    B->>API: update {notes:"fundos"} baseVersion=1
    API-->>B: applied, version 3 (campo diferente: mescla)
    B->>API: update {number:"30"} baseVersion=1
    API-->>B: conflict version_conflict fields=[number], server={number:"20", version:3}
    B->>B: aplica server; guarda conflito; mostra ao motorista
    B->>API: (se escolher "Usar a minha versão") update {number:"30"} baseVersion=3, operationId novo
    API-->>B: applied, version 4
```

### Primeiro login com dados locais

```mermaid
sequenceDiagram
    participant App
    participant Auth as Supabase Auth
    participant API

    App->>Auth: signIn (e-mail/senha ou OTP)
    Auth-->>App: access_token (JWT) + refresh_token
    App->>API: GET /v1/me (cria o perfil)
    App->>API: POST /v1/devices {id, platform, model, appVersion}
    App->>App: gera UUID para linhas sem uuid; enfileira create de tudo em ordem de dependência
    loop até a fila esvaziar
        App->>API: POST /v1/sync/push (≤500)
    end
    App->>API: GET /v1/sync/pull?since=0 (até hasMore=false)
```

## 6. O que o app Flutter precisa ganhar

Feito depois, pelo lead. Especificação exata:

### 6.1 Banco (migration nova em `lib/data/database.dart`)

| Tabela | Colunas novas | Observação |
|---|---|---|
| `deliveries`, `routes`, `route_stops`, `delivery_events`, `route_plans`, `vehicles`, `oil_changes`, `shifts`, `base_location` | `uuid TEXT` (UNIQUE, preenchido na criação com UUID v4), `server_version INTEGER NOT NULL DEFAULT 0` (0 = nunca sincronizado) | O `id INTEGER` local continua sendo a chave interna. Nas operações, toda referência vai pelo **uuid** (`routeId`, `deliveryId`, `vehicleId`). Migration preenche `uuid` das linhas existentes. |
| `routes` | `deleted_at TEXT` opcional | Hoje a rota é apagada de verdade; pode continuar assim desde que a operação `delete` seja enfileirada antes. |
| **nova** `sync_queue` | `id INTEGER PK`, `operation_id TEXT UNIQUE NOT NULL`, `entity_type TEXT NOT NULL`, `entity_uuid TEXT NOT NULL`, `operation_type TEXT NOT NULL`, `payload TEXT NOT NULL` (JSON), `base_version INTEGER`, `created_at TEXT NOT NULL` (UTC), `status TEXT NOT NULL DEFAULT 'pending'` (`pending`/`sent`/`conflict`/`rejected`), `attempts INTEGER NOT NULL DEFAULT 0`, `result TEXT` (JSON da resposta), `updated_at TEXT` | Índice `(status, id)`. Linhas `sent` podem ser apagadas depois de 7 dias. |
| `settings` | chaves `device_id` (UUID gerado uma vez), `sync_cursor` (`"0"`), `sync_last_success_at`, `account_user_id` | Ao trocar de conta: limpar fila e cursor. |

### 6.2 Fluxos

1. **Outbox**: cada método de repositório que muda uma entidade sincronizável insere a operação na `sync_queue` **na mesma transação** (`insert` → `create`; `update` → `update` só com os campos mudados — já existe `changedEditableFields`; `transition` → `transition` com `eventId` = uuid do evento gravado; `reorder`/`saveRouteOrder` → `reorder` com os uuids das paradas abertas; `delete` → `delete`). Só enfileira se houver conta logada.
2. **baseVersion** = `server_version` da linha no momento da mudança.
3. **Datas**: mandar sempre em UTC com sufixo `Z` (`toUtc().toIso8601String()`); hoje o SQLite guarda horário local sem fuso.
4. **Nomes**: payload em camelCase (`customer_name` → `customerName`); enums iguais aos do app (`PENDING`, `ABSENT`, `motorcycle`…); `changed_fields` vira array.
5. **Turno**: não mandar `track_points`. Ao encerrar o turno, gerar `track = {polyline, pointCount, startedAt, endedAt, bbox}` (polyline codificada, simplificada ~10 m) e mandar `update` do `shift`.
6. **Envio**: quando houver rede + sessão, pegar até 500 `pending` em ordem de `id` e chamar o push. Tratar cada resultado (§2). Erro de rede/5xx: manter `pending`, backoff exponencial (5 s → 10 min). 401: renovar o token (supabase_flutter faz) e tentar de novo.
7. **Recebimento**: depois de cada push, pull até `hasMore = false`. Para cada mudança: achar a linha por `uuid`; se `server_version >= version`, ignorar; se a entidade tem operações `pending`, adiar (aplicar no próximo ciclo); senão gravar `data` (ou exclusão lógica/remoção no tombstone) e `server_version = version`. Salvar `sync_cursor` na mesma transação da página.
8. **Primeiro login**: `POST /v1/devices`; enfileirar `create` de tudo em ordem: `vehicle` → `base_location` → `delivery` → `route` → `route_stop` → `route_plan` → `delivery_event` → `oil_change` → `shift`; depois push/pull.
9. **Conflito**: aplicar `server` localmente, marcar a operação como `conflict` e mostrar (§4). **Recusada**: marcar `rejected` e mostrar no relatório de erros (sem dados pessoais).
10. **Sem conta**: nada muda. A sincronização é opcional.

### 6.3 Chamadas HTTP

- Base: `--dart-define=API_BASE_URL=https://…/v1`. Login com `supabase_flutter` (só `SUPABASE_URL` e `SUPABASE_ANON_KEY` via `--dart-define`; nunca a service_role).
- Cabeçalhos: `Authorization: Bearer <session.accessToken>`, `x-request-id` opcional (UUID) para suporte.
- Erros HTTP vêm sempre como `{statusCode, error, message, details?, path, timestamp, requestId}`.
