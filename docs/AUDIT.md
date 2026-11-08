# Auditoria do projeto existente

Data: 08/11/2026 · Base: commit `106c51b` ("Implantação Rota MAx") · Escopo: checklist da seção 20 do [PRD](PRD.md).

O código auditado é o app **Rota Food** (pacote Dart `rota_pizza`, applicationId `com.rotapizza.rota_pizza`), versão `1.1.2+6`. Os caminhos abaixo são os do commit auditado.

## 1. Funcionalidades concluídas

| Funcionalidade | Onde |
|---|---|
| Cadastro, edição e exclusão de entregas | `screens/add_delivery_screen.dart`, `screens/delivery_detail_screen.dart` |
| Colar vários endereços / texto do WhatsApp com prévia | `screens/paste_addresses_screen.dart`, `AddressParser.parseBatch` |
| OCR de até 5 fotos (ML Kit, no aparelho) com conferência antes de salvar | `services/ocr_service.dart`, `screens/scan_tickets_screen.dart` |
| Geocodificação Nominatim com até 5 candidatos e confirmação no mapa | `services/geocoding_service.dart`, `screens/confirm_location_screen.dart` |
| Otimização por vizinho mais próximo com peso de prioridade | `services/route_optimizer.dart:49-73` |
| Reotimização automática após "Entregue", preservando concluídas | `providers/app_state.dart:242-255`, `sqlite_delivery_repository.dart:46-61` |
| Navegação no Google Maps pelo texto do endereço | `services/maps_service.dart:9-35` |
| Turno com GPS em foreground service, km, combustível, óleo | `services/shift_tracker.dart`, `core/utils/maintenance.dart` |
| Relatório do turno com linha do tempo e envio por WhatsApp | `screens/shift_report_screen.dart` |
| Turno aberto sobrevive ao fechamento do app | `providers/app_state.dart:130-134` |
| Detecção de duplicidade contra pendentes | `providers/app_state.dart:149-160` |

## 2. Parcialmente implementadas

| Item | O que falta |
|---|---|
| Importação em lote | Itens colados são salvos **sem coordenadas** (`app_state.dart:384`). Não há CSV/Excel |
| OCR | Não extrai CEP nem bairro; não sinaliza baixa confiança; geocode com falha é **descartado em silêncio** ao salvar (`scan_tickets_screen.dart:196`) |
| Otimização | Sem 2-opt; distância e tempo só em linha reta (28 km/h); sem reordenação manual; sem tela de revisão antes de iniciar |
| Mapa | Existe só para confirmar pino e no relatório. Não há mapa das paradas nem posição atual |
| Navegação externa | Só Google Maps; **sem Waze** |
| Dashboard | Usa `companyId: 'local-company'`, mostra tendências inventadas (+12%, +8%) (`models/dashboard.dart:48-69`) |
| Banco | Migrations com `if (oldVersion < N)` sem registro; sem FKs; sem índices; transação só em 2 pontos |
| Recuperação de sessão | Ordem da rota sobrevive, mas não há entidade "rota" nem "próxima parada" persistida |

## 3. Inexistentes

- Status `IN_PROGRESS`, `FAILED`, `SKIPPED` (hoje só `pending`/`done`, `models/delivery.dart:1`).
- Motivos de insucesso e histórico de eventos (`delivery_events`).
- Tabelas `routes` / `route_stops`.
- Campos `postal_code`, `state`, `notes`, `package_id`, `updated_at`.
- Aviso de GPS desligado (`location_service.dart:9-11` retorna `null` em silêncio).
- Exclusão de todos os dados pelo usuário.
- Assinatura de release e preparação para a Play Store.

## 4. Bugs encontrados

1. **Dados de demonstração em produção.** `DemoShiftSeeder` roda a cada início (`main.dart:19`, `database.dart:97,109`). Em todo app sem turnos, ele grava um turno falso com 7 clientes fictícios, **troca o ponto de saída do usuário por "Forno da Vila" e sobrescreve as configurações do veículo**. A flag `demo_linkedin_shift_v1` é gravada mas nunca lida.
2. **Cache de geocodificação nunca é lido.** `cacheConfirmed` grava em `geocode_cache`, mas `search()` não consulta o cache: toda busca vai à rede.
3. **Dashboard: "Km por entrega" mostra entregas por entregador** (`dashboard_screen.dart:69-70`).
4. **Dashboard com tendências fixas** que não vêm de dado nenhum.
5. Subtítulo do relatório fixo em "São Bernardo do Campo" (`shift_report_screen.dart:111`), independente da cidade do usuário.

## 5. Problemas arquiteturais

- `AppState` concentra quase toda a regra de negócio (estado, rota, importação, turno). Aceitável no tamanho atual, mas toda nova regra de status deve ir para o repositório/serviço, não para a tela.
- Ordem da rota é uma coluna da entrega (`route_order`), não uma rota. Impede histórico de rotas e mais de uma rota por dia.
- Código de plataforma (auth, empresas, operação) e Supabase existem só como esqueleto **não usado no app**, com `SUPABASE_SERVICE_ROLE_KEY` prevista no cliente e RLS `using (true)` no `supabase/schema.sql`.
- Nomes divergentes: pasta Rota-Fast, pacote `rota_pizza`, app "Rota Food", docs "Rota Pizza", Supabase "Rota Max".

## 6. Dependências

Versões travadas no `pubspec.lock`: `sqflite 2.4.3`, `geolocator 14.0.3`, `flutter_map 8.3.2`, `google_mlkit_text_recognition 0.17.1`, `provider 6.1.5+1`, `image_picker 1.2.3`, `url_launcher 6.3.2`, `http 1.6.0`, `intl 0.20.3`.

- `supabase_flutter`: inicializado e não usado.
- `cupertino_icons`: não usado.
- CI (`.github/workflows/ci.yml`) usa `channel: stable` sem versão fixa.

## 7. Riscos técnicos

| Risco | Impacto | Mitigação |
|---|---|---|
| Política de uso do Nominatim público (proíbe uso pesado por apps distribuídos) | Bloqueio por IP/UA com muitos parceiros | Cache lido de verdade, 1 req/s, UA identificável; avaliar provedor pago/instância própria na v1.1 |
| Localização em segundo plano na Play Store | Reprovação na revisão | Declaração de foreground service + vídeo + política de privacidade |
| Release assinado com chave debug | Play Store recusa | Keystore de upload + Play App Signing |
| applicationId template | Permanente após publicar | Trocar antes: `com.rotamax.app` |
| Flutter fora do PATH na máquina de desenvolvimento | Sem validação local | Instalar SDK; CI como rede de segurança |

## 8. Próximas tarefas recomendadas

Ver o plano em etapas no [BACKLOG.md](BACKLOG.md): rebrand e limpeza → fundação do banco → execução e recuperação → roteirização → mapa e navegação → correções de pedidos/OCR → dashboard/histórico → Play Store.
