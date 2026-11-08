# Comparação: Requisitos Funcionais v1.0 × código

Atualizado em 08/11/2026, branch `rota-max-v1` (249 testes do app + 102 da API passando).
Requisitos completos em [REQUIREMENTS.md](REQUIREMENTS.md).

Legenda: ✅ feito e testado · 🟡 parcial · ❌ falta · 📱 falta validar em Android real (Definição de Pronto §8)

> Nada abaixo foi validado em aparelho ainda: **todo item ✅ também é 📱** até o primeiro teste no celular.

## RF-001 — Otimização inteligente (P0)
| Item | Situação | Onde |
|---|---|---|
| Ponto inicial | ✅ GPS → ponto de saída | `AppState.organizeRoute` |
| Ponto final opcional | ✅ no motor e na rota (`routes.end_lat/lng`) · 🟡 sem tela para escolher o ponto final | `RoutingRequest.end`, `AppState.setEndPoint` |
| Ordem automática | ✅ vizinho mais próximo + 2-opt + Or-opt | `lib/services/routing/route_solver.dart` |
| Malha viária real | ✅ matriz OpenRouteService (carro / caminhão) · 📱 não testado contra a API real (precisa de `ORS_API_KEY`) | `ors_matrix_client.dart` |
| Evitar voltas e cruzamentos | ✅ teste QA-003 (20 paradas, 4 bairros, sem cruzamento) | `test/routing/route_engine_test.dart` |
| Distância e tempo totais | ✅ da rota salva; painel na mesma escala | `routes.estimated_*`, `AppState.summary` |
| Recalcular | ✅ | "Organizar rota", "Recalcular respeitando travas" |
| Preservar concluídas | ✅ | `saveRouteOrder` (testado no SQLite e em memória) |
| Avisar não roteável | ✅ lista os nomes no aviso | `RoutingResult.unroutable` |
| Falhou → mantém sequência | ✅ motor nunca lança; gravação em transação | `DefaultRouteEngine.plan`, `_action` |
| Sem bloquear a tela (RNF-004) | ✅ cálculo em isolate; painel não otimiza mais | `compute()`; 40 paradas < 300 ms |

## RF-002 — Edição manual (P1)
| Item | Situação |
|---|---|
| Arrastar e soltar | ✅ tela "Editar ordem" |
| Subir / descer | ✅ |
| Fixar posição (alfinete) | ✅ |
| Travar parada (cadeado) | ✅ respeitado pelo motor e na reotimização |
| Recalcular após edição | ✅ "Recalcular respeitando travas" |
| Desfazer | ✅ até 20 passos |
| Numeração atualizada | ✅ |
| Ordem manual sobrevive a fechar o app | ✅ teste com SQLite em arquivo (QA-005/QA-008) |
| Concluídas não se movem | ✅ |

## RF-003 — Endereços (P0)
| Item | Situação |
|---|---|
| Pesquisar | ✅ erro 400 corrigido (`q` **ou** busca estruturada); cache lido antes da rede |
| Sugerir enquanto digita | ✅ autocompletar ORS · 📱 depende de `ORS_API_KEY` |
| Endereço incompleto | ✅ selo no formulário e na lista |
| Ver no mapa | ✅ |
| Ajuste manual do pino | ✅ arrastar; abre o mapa mesmo sem resultado |
| Número, complemento, CEP, referência | ✅ |
| Alerta de não localizado | ✅ com "Marcar no mapa" |
| Duplicados sem excluir | ✅ "Salvar mesmo assim"; importação lista os prováveis duplicados |
| Editar endereço apaga pino antigo | ✅ |

## RF-004 — Estabilidade (P0)
| Item | Situação |
|---|---|
| Salvar automaticamente / persistência local | ✅ SQLite, transações |
| Recuperar rota, sequência e status | ✅ |
| Após reiniciar o aparelho | ✅ dados · 🟡 GPS do turno só volta quando o app é aberto · 📱 QA-009 |
| Evitar duplicidade | ✅ trava contra toque duplo; duplicados avisados |
| Informar falhas sem fechar | ✅ `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError`; ações viram mensagem; tela "Não foi possível abrir os dados" com "Tentar de novo" |
| Rascunhos (formulário e OCR) | ✅ |

## RF-005 — Persistência e histórico
| Item | Situação |
|---|---|
| Rotas e entregas salvas | ✅ |
| Histórico de rotas / abrir anteriores | ✅ tela "Histórico de rotas", "Reabrir esta rota" |
| Excluir rota com confirmação, sem afetar outras | ✅ |
| Editar pendentes | ✅ |
| Offline | ✅ |
| Histórico de alterações e tentativas | ✅ eventos de status e de edição (campos alterados); exclusão lógica |
| Backup / trocar de celular | 🟡 backend pronto (`apps/api`), **sincronização no app ainda não feita** |

## RF-006 — GPS (P1)
| Item | Situação |
|---|---|
| Pedir permissão | ✅ |
| GPS desligado | ✅ faixa "GPS desligado — Ativar" |
| Posição atual no mapa | ✅ mapa da rota |
| Atualizar durante a rota | ✅ durante o turno |
| Sinal indisponível | ✅ aviso + religa sozinho |
| Última posição como desatualizada | ✅ |
| Tentar de novo | ✅ com espera crescente |
| Falha do GPS não bloqueia a rota | ✅ |

## Plano de testes (QA)
| Teste | Automatizado | No aparelho |
|---|---|---|
| QA-001 / 002 / 003 | ✅ | 📱 |
| QA-004 (40 paradas sem travar) | ✅ < 300 ms | 📱 |
| QA-005 reorganizar | ✅ | 📱 |
| QA-006 endereço inválido | ✅ | 📱 |
| QA-007 duplicado | ✅ | 📱 |
| QA-008 fechar o app | ✅ (SQLite em arquivo) | 📱 |
| QA-009 reiniciar o aparelho | — | 📱 |
| QA-010 GPS desligado | ✅ (GPS falso) | 📱 |
| QA-011 sem internet | ✅ (cliente falso) | 📱 |
| QA-012 reotimizar em andamento | ✅ | 📱 |

## Pendências
1. **Validação em Android real** (Definição de Pronto): aguardando o celular em depuração USB.
2. **Chave do OpenRouteService** para testar ruas reais e autocompletar.
3. **Sincronização no app** (UUID, fila `sync_queue`, login opcional): especificada em [api/sync-protocol.md §6](api/sync-protocol.md).
4. **Backend**: aplicar a migration num projeto Supabase de teste (RLS, PostGIS e índices ainda não rodaram num Postgres real).
5. Tela de **relatórios** (economia por dia/semana/mês) usando `route_plans`.
6. Tela para escolher o **ponto final** da rota.
7. Play Store: assinatura, política de privacidade, ficha.
